--- Spaced Repetition System (SRS) module for obsidian.nvim
local Path = require "obsidian.path"
local log = require "obsidian.log"
local search = require "obsidian.search"
local async = require "plenary.async"
local channel = require("plenary.async.control").channel

local M = {}

---@class obsidian.srs.Card
---@field question string
---@field answer string
---@field file_path string
---@field line_num integer
---@field due_date string|?
---@field interval integer
---@field ease integer
---@field is_new boolean
---@field is_reversed boolean
---@field is_cloze boolean
---@field cloze_num integer|?
---@field raw_line string
---@field is_block boolean|?
---@field block_lines string[]|?
---@field block_markers table[]|?

M.DEFAULT_EASE = 250
M.MIN_EASE = 130
M.DEFAULT_INTERVAL = 1

-- Patterns for ripgrep search
M.CARD_SEPARATOR_PATTERN = "(::[:]?|^\\s*\\?\\??\\s*$)"
M.CLOZE_PATTERN = "(\\{\\{[cfrpelsv]\\d+::|==)"

M.strip_schedule_comment = function(s)
  local stripped = string.gsub(s, "%s*<!%-%-SR:!?[^%-]%-%->{0,1}%s*$", "")
  stripped = string.gsub(stripped, "%s*<!%-%-SR:[^>]*%-%->%s*$", "")
  return stripped
end

M.parse_card_line = function(line)
  local q, a = string.match(line, "^(.-)%s*:::%s*(.+)$")
  if q and a then return q, M.strip_schedule_comment(a), true end
  q, a = string.match(line, "^(.-)%s*::%s*(.+)$")
  if q and a then return q, M.strip_schedule_comment(a), false end
  return nil, nil, false
end

--- Compatibility wrapper for old cloze parsing
M.parse_cloze_line = function(line)
  -- Try implicit highlight first
  local q, a, rest = string.match(line, "^(.-)==([^=]+)==(.-)$")
  if q and a then
    return q .. "[...]" .. rest, a, 1
  end
  -- Try implicit bold
  q, a, rest = string.match(line, "^(.-)%*%*([^%*]+)%*%*(.-)$")
  if q and a then
    return q .. "[...]" .. rest, a, 1
  end
  -- Try standard cloze
  local type, num, text
  q, type, num, text, rest = string.match(line, "^(.-){{([cfrpelsv])(%d+)::([^}]+)}}(.-)$")
  if q and text then
    return q .. "[...]" .. rest, text, tonumber(num)
  end
  return nil, nil, nil
end

--- Create a card object from a line (for testing and manual parsing)
M.card_from_line = function(line, path, line_num, all_lines)
  if line == "?" or line == "??" then
    if not all_lines then return nil end
    local is_reversed = line == "??"
    local q_lines, a_lines = {}, {}
    for i = line_num - 1, 1, -1 do
      if string.match(all_lines[i] or "", "^%s*$") then break end
      table.insert(q_lines, 1, all_lines[i])
    end
    local due_date, interval, ease, answer_end_line
    for i = line_num + 1, #all_lines do
      if string.match(all_lines[i] or "", "^%s*$") then break end
      answer_end_line = i
      local l = all_lines[i]
      if string.match(l, "<!%-%-SR:[^>]*%-%->") then
        due_date, interval, ease = M.parse_schedule_comment(l)
        l = M.strip_schedule_comment(l)
      end
      table.insert(a_lines, l)
    end
    local q, a = table.concat(q_lines, "\n"):match("^%s*(.-)%s*$"), table.concat(a_lines, "\n"):match("^%s*(.-)%s*$")
    if q and a then
      return { question = q, answer = a, file_path = path, line_num = line_num, answer_end_line = answer_end_line,
               due_date = due_date, interval = interval or 0, ease = ease or M.DEFAULT_EASE, 
               is_new = not due_date, is_reversed = is_reversed, is_cloze = false, layout_type = "classic" }
    end
  else
    local q, a, is_reversed = M.parse_card_line(line)
    if q and a then
      local due_date, interval, ease = M.parse_schedule_comment(line)
      return { question = q, answer = a, file_path = path, line_num = line_num,
               due_date = due_date, interval = interval or 0, ease = ease or M.DEFAULT_EASE, 
               is_new = not due_date, is_reversed = is_reversed, is_cloze = false, layout_type = "classic" }
    end
  end
  return nil
end

--- Extract all markers from a line
M.extract_markers = function(line)
  local markers = {}
  -- Standard: {{f1::text}}
  for type, num, text in string.gmatch(line, "{{([cfrpelsv])(%d+)::([^}]+)}}") do
    table.insert(markers, { type = type, num = tonumber(num), text = text, raw = "{{" .. type .. num .. "::" .. text .. "}}" })
  end
  -- Implicit Highlight (c1)
  for text in string.gmatch(line, "==([^=]+)==") do
    table.insert(markers, { type = "c", num = 1, text = text, raw = "==" .. text .. "==" })
  end
  return markers
end

M.parse_system_line = function(line, target_id)
  local util = require "obsidian.util"
  local markers = M.extract_markers(line)
  if #markers == 0 then return nil end

  local question = line
  local answers = {}
  for _, m in ipairs(markers) do
    local id = m.type .. m.num
    local pattern = util.escape_magic_characters(m.raw)
    if id == target_id then
      question = string.gsub(question, pattern, "[...]")
      table.insert(answers, m.text)
    else
      question = string.gsub(question, pattern, m.text)
    end
  end
  return M.strip_schedule_comment(question), table.concat(answers, ", ")
end

M.parse_schedule_comment = function(line)
  local date, interval, ease = string.match(line, "<!%-%-SR:!([%d%-]+),(%d+),(%d+)%-%->")
  return date, tonumber(interval), tonumber(ease)
end

M.build_schedule_comment = function(due_date, interval, ease)
  return string.format("<!--SR:!%s,%d,%d-->", due_date, interval, ease)
end

M.sm2 = function(grade, interval, ease)
  if grade < 3 then return 1, math.max(M.MIN_EASE, ease - 20) end
  local new_interval = interval == 0 and 1 or (interval == 1 and 6 or math.ceil(interval * (ease / 100)))
  local delta = math.floor((0.1 - (5 - grade) * (0.08 + (5 - grade) * 0.02)) * 100)
  return new_interval, math.max(M.MIN_EASE, ease + delta)
end

M.button_to_grade = function(button)
  local grades = { again = 1, hard = 3, good = 4, easy = 5 }
  return grades[button] or 4
end

M.next_due_date = function(interval)
  return os.date("%Y-%m-%d", os.time() + (interval * 86400))
end

M.today = function() return os.date("%Y-%m-%d", os.time()) end
M.is_due = function(date) return not date or date <= M.today() end

M.days_until_due = function(date)
  if not date then return 0 end
  local today = M.today()
  if date <= today then return 0 end
  
  local y1, m1, d1 = string.match(today, "(%d+)-(%d+)-(%d+)")
  local y2, m2, d2 = string.match(date, "(%d+)-(%d+)-(%d+)")
  
  local t1 = os.time({year = tonumber(y1), month = tonumber(m1), day = tonumber(d1), hour = 12})
  local t2 = os.time({year = tonumber(y2), month = tonumber(m2), day = tonumber(d2), hour = 12})
  
  return math.floor(os.difftime(t2, t1) / 86400)
end

M.get_heading_trace = function(lines, line_num)
  local trace = {}
  local current_level = 7 -- Higher than any possible Markdown header
  
  for i = line_num - 1, 1, -1 do
    local line = lines[i] or ""
    local hashes, header_text = string.match(line, "^(#+)%s+(.*)$")
    if hashes then
      local level = #hashes
      if level < current_level then
        -- Clean up header text (remove trailing schedule comments or tags if needed, but let's keep it simple first)
        local clean_text = M.strip_schedule_comment(header_text):gsub("%s*$", "")
        table.insert(trace, 1, clean_text)
        current_level = level
      end
    end
    if current_level == 1 then break end
  end
  
  return #trace > 0 and table.concat(trace, " > ") or nil
end

--- Check if a file has unsaved changes in any open buffer.
---@param file_path string
---@return boolean
M.has_unsaved_changes = function(file_path)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    local buf_name = vim.api.nvim_buf_get_name(bufnr)
    if buf_name == file_path then
      return vim.api.nvim_get_option_value("modified", { buf = bufnr })
    end
  end
  return false
end

--- Update a card's scheduling info in-place in the file after a review.
---@param card obsidian.srs.Card
---@param button string "again"|"hard"|"good"|"easy"
---@return boolean success
M.review_card = function(card, button)
  if M.has_unsaved_changes(card.file_path) then
    log.err("Cannot update card: %s has unsaved changes. Save the file first.", card.file_path)
    return false
  end

  local grade = M.button_to_grade(button)
  local new_interval, new_ease = M.sm2(grade, card.interval, card.ease)
  local new_due = M.next_due_date(new_interval)
  local new_comment = M.build_schedule_comment(new_due, new_interval, new_ease)

  local file_path = card.file_path
  local lines = {}
  local f = io.open(file_path, "r")
  if not f then
    log.err("Failed to open file for SRS update: %s", file_path)
    return false
  end

  for line in f:lines() do
    lines[#lines + 1] = line
  end
  f:close()

  local target_line_idx = card.answer_end_line or card.line_num

  if target_line_idx > #lines then
    log.err("SRS card line number %d exceeds file length %d in %s", target_line_idx, #lines, file_path)
    return false
  end

  local old_line = lines[target_line_idx]

  local new_line = string.gsub(old_line, "%s*<!%-%-SR:[^>]*%-%->%s*$", "")
  new_line = new_line .. " " .. new_comment

  lines[target_line_idx] = new_line

  f = io.open(file_path, "w")
  if not f then
    log.err("Failed to write file for SRS update: %s", file_path)
    return false
  end

  for _, line in ipairs(lines) do
    f:write(line .. "\n")
  end
  f:close()

  card.due_date = new_due
  card.interval = new_interval
  card.ease = new_ease
  card.is_new = false

  log.info("Reviewed card: next due %s (interval=%d, ease=%d)", new_due, new_interval, new_ease)
  return true
end

M.find_cards_async = function(dir, callback, opts)
  opts = opts or {}
  local cards = {}
  local tx, rx = channel.oneshot()
  local file_cache = {}
  local note_cache = {}

  local Note = require "obsidian.note"

  search.search_async(dir, M.CARD_SEPARATOR_PATTERN, nil, function(match)
    local path = tostring(Path.new(match.path.text):resolve())
    
    -- Parse note once per file to check tags
    if not note_cache[path] then
      note_cache[path] = Note.from_file(path, { max_lines = 100 })
    end
    local note = note_cache[path]

    -- Tag filter check (from frontmatter)
    if opts.tag then
      local has_tag = false
      for _, t in ipairs(note.tags) do
        -- Normalize tag (remove leading #)
        local normalized_t = t:gsub("^#", "")
        local normalized_filter = opts.tag:gsub("^#", "")
        if normalized_t == normalized_filter then
          has_tag = true
          break
        end
      end
      if not has_tag then return end
    end

    if not file_cache[path] then
      local f = io.open(path, "r")
      if f then
        file_cache[path] = {}
        for l in f:lines() do table.insert(file_cache[path], l) end
        f:close()
      end
    end
    
    local line_num = match.line_number
    local lines = file_cache[path]
    local line = lines[line_num]
    
    -- Find header trace for context
    local section = M.get_heading_trace(lines, line_num)
    
    local due_date, interval, ease, q, a, is_reversed, answer_end_line
    if string.match(line, "^%s*%?%??%s*$") then
      is_reversed = string.match(line, "%?%?") ~= nil
      local q_lines, a_lines = {}, {}
      for i = line_num - 1, 1, -1 do
        if string.match(lines[i] or "", "^%s*$") then break end
        table.insert(q_lines, 1, lines[i])
      end
      for i = line_num + 1, #lines do
        if string.match(lines[i] or "", "^%s*$") then break end
        answer_end_line = i
        local l = lines[i]
        if string.match(l, "<!%-%-SR:[^>]*%-%->") then
          due_date, interval, ease = M.parse_schedule_comment(l)
          l = M.strip_schedule_comment(l)
        end
        table.insert(a_lines, l)
      end
      q, a = table.concat(q_lines, "\n"):match("^%s*(.-)%s*$"), table.concat(a_lines, "\n"):match("^%s*(.-)%s*$")
      if q and a and q ~= "" and a ~= "" then
        table.insert(cards, { question = q, answer = a, file_path = path, line_num = line_num, answer_end_line = answer_end_line,
                             due_date = due_date, interval = interval or 0, ease = ease or M.DEFAULT_EASE, 
                             is_new = not due_date, is_reversed = is_reversed, is_cloze = false, layout_type = "classic",
                             section = section })
      end
    else
      q, a, is_reversed = M.parse_card_line(line)
      if q and a then
        due_date, interval, ease = M.parse_schedule_comment(line)
        table.insert(cards, { question = q, answer = a, file_path = path, line_num = line_num,
                             due_date = due_date, interval = interval or 0, ease = ease or M.DEFAULT_EASE, 
                             is_new = not due_date, is_reversed = is_reversed, is_cloze = false, layout_type = "classic",
                             section = section })
      end
    end
  end, function() tx() end)

  async.run(function() rx(); return cards end, callback)
end

M.find_system_blocks_async = function(dir, callback, opts)
  opts = opts or {}
  local cards = {}
  local tx, rx = channel.oneshot()
  local file_cache = {}
  local note_cache = {}

  local Note = require "obsidian.note"

  search.search_async(dir, M.CLOZE_PATTERN, nil, function(match)
    local path = tostring(Path.new(match.path.text):resolve())
    
    -- Parse note once per file to check tags
    if not note_cache[path] then
      note_cache[path] = Note.from_file(path, { max_lines = 100 })
    end
    local note = note_cache[path]

    -- Tag filter check (from frontmatter)
    if opts.tag then
      local has_tag = false
      for _, t in ipairs(note.tags) do
        -- Normalize tag (remove leading #)
        local normalized_t = t:gsub("^#", "")
        local normalized_filter = opts.tag:gsub("^#", "")
        if normalized_t == normalized_filter then
          has_tag = true
          break
        end
      end
      if not has_tag then return end
    end

    if not file_cache[path] then
      local f = io.open(path, "r")
      if f then
        file_cache[path] = {}
        for l in f:lines() do table.insert(file_cache[path], l) end
        f:close()
      end
    end

    local lines = file_cache[path]
    local start_ln = match.line_number
    
    -- Find header trace for context
    local section = M.get_heading_trace(lines, start_ln)
    
    -- Find block boundaries (contiguous text)
    local b_start = start_ln
    while b_start > 1 and not string.match(lines[b_start - 1] or "", "^%s*$") do
      b_start = b_start - 1
    end
    
    local b_end = start_ln
    local schedule_line = nil
    while b_end < #lines and not string.match(lines[b_end + 1] or "", "^%s*$") do
      b_end = b_end + 1
      if string.match(lines[b_end], "<!%-%-SR:[^>]*%-%->") then
        schedule_line = lines[b_end]
      end
    end
    if not schedule_line and string.match(lines[start_ln], "<!%-%-SR:[^>]*%-%->") then
      schedule_line = lines[start_ln]
    end

    local block_key = path .. ":" .. b_start .. ":" .. b_end
    if file_cache[block_key] then return end -- Avoid duplicates for same block
    file_cache[block_key] = true

    local block_lines = {}
    local block_markers = {}
    for i = b_start, b_end do
      local l = lines[i]
      table.insert(block_lines, M.strip_schedule_comment(l))
      local ms = M.extract_markers(l)
      for _, m in ipairs(ms) do
        m.line_idx = i - b_start + 1
        table.insert(block_markers, m)
      end
    end

    if #block_markers > 0 then
      local d, i, e = nil, nil, nil
      if schedule_line then d, i, e = M.parse_schedule_comment(schedule_line) end
      
      local layout_type = "system"
      if #block_lines == 1 and #block_markers == 1 then
        layout_type = "classic"
      end

      table.insert(cards, {
        file_path = path,
        line_num = b_end,
        due_date = d,
        interval = i or 0,
        ease = e or M.DEFAULT_EASE,
        is_new = not d,
        is_cloze = true,
        is_block = true,
        block_lines = block_lines,
        block_markers = block_markers,
        layout_type = layout_type,
        section = section,
      })
    end
  end, function() tx() end)

  async.run(function() rx(); return cards end, callback)
end

--- Compatibility wrapper for old cloze search
M.find_cloze_cards_async = function(dir, callback, opts)
  local util = require "obsidian.util"
  M.find_system_blocks_async(dir, function(blocks)
    local legacy_cards = {}
    for _, b in ipairs(blocks) do
      -- The old test expects one card per marker if they are on the same line,
      -- or at least it expects the legacy format.
      for _, m in ipairs(b.block_markers or {}) do
        -- Find the line containing this marker
        local line = b.block_lines[m.line_idx]
        if line then
          local question = line:gsub(util.escape_magic_characters(m.raw), "[...]")
          -- Strip other markers from the question for simple display
          for _, other_m in ipairs(b.block_markers) do
            if other_m.raw ~= m.raw then
              question = question:gsub(util.escape_magic_characters(other_m.raw), other_m.text)
            end
          end
          
          table.insert(legacy_cards, {
            question = question,
            answer = m.text,
            cloze_num = m.num,
            file_path = b.file_path,
            line_num = b.line_num,
            due_date = b.due_date,
            interval = b.interval,
            ease = b.ease,
            is_new = b.is_new,
            is_cloze = true,
            section = b.section
          })
        end
      end
    end
    callback(legacy_cards)
  end, opts)
end

M.load_stats = function()
  local f = io.open(M.get_stats_file(), "r")
  if not f then return { total_reviews = 0, daily_stats = {}, streak = 0 } end
  local content = f:read("*all")
  f:close()
  if content == "" then return { total_reviews = 0, daily_stats = {}, streak = 0 } end
  local ok, s = pcall(vim.json.decode, content)
  return ok and s or { total_reviews = 0, daily_stats = {}, streak = 0 }
end

M.save_stats = function(s)
  local f = io.open(M.get_stats_file(), "w")
  if f then f:write(vim.json.encode(s)); f:close() end
end

M.update_stats = function(rev, new)
  local s, t = M.load_stats(), M.today()
  s.daily_stats = s.daily_stats or {}
  s.daily_stats[t] = s.daily_stats[t] or { reviews = 0, new_cards = 0 }
  s.daily_stats[t].reviews = s.daily_stats[t].reviews + rev
  s.daily_stats[t].new_cards = s.daily_stats[t].new_cards + new
  s.total_reviews = (s.total_reviews or 0) + rev
  s.streak = (s.last_review_date == t) and s.streak or (s.last_review_date == os.date("%Y-%m-%d", os.time() - 86400) and s.streak + 1 or 1)
  s.last_review_date = t
  M.save_stats(s)
end

M.get_stats_summary = function()
  local s = M.load_stats()
  local d = (s.daily_stats or {})[M.today()] or { reviews = 0, new_cards = 0 }
  return { total_reviews = s.total_reviews or 0, today_reviews = d.reviews, today_new_cards = d.new_cards, streak = s.streak or 0 }
end

M.get_upcoming_reviews = function(cards, days)
  local up = {}
  for i = 0, days do up[os.date("%Y-%m-%d", os.time() + (i * 86400))] = 0 end
  for _, c in ipairs(cards) do if c.due_date and up[c.due_date] then up[c.due_date] = up[c.due_date] + 1 end end
  return up
end

--- Apply review limits from config
M.apply_review_limits = function(cards, config)
  config = config or {}
  local max_new = config.max_new_per_day or 20
  local max_total = config.max_reviews_per_day or 100

  local stats = M.load_stats()
  local today = M.today()
  local today_stats = (stats.daily_stats or {})[today] or { reviews = 0, new_cards = 0 }

  local new_count = today_stats.new_cards or 0
  local total_count = today_stats.reviews or 0

  local filtered = {}
  for _, card in ipairs(cards) do
    if total_count >= max_total then
      break
    end

    if card.is_new then
      if new_count < max_new then
        table.insert(filtered, card)
        new_count = new_count + 1
        total_count = total_count + 1
      end
    else
      table.insert(filtered, card)
      total_count = total_count + 1
    end
  end

  return filtered
end

--- Filter cards by tags
M.filter_by_tags = function(cards, tags)
  if not tags or #tags == 0 then
    return cards
  end

  local tag_set = {}
  for _, tag in ipairs(tags) do
    tag_set[tag] = true
  end

  local filtered = {}
  for _, card in ipairs(cards) do
    local content = ""
    if card.is_block then
      content = table.concat(card.block_lines, " ")
    else
      content = (card.question or "") .. " " .. (card.answer or "")
    end

    local card_tags = M.extract_tags(content)
    for _, card_tag in ipairs(card_tags) do
      if tag_set[card_tag] then
        table.insert(filtered, card)
        break
      end
    end
  end

  return filtered
end

--- Get all unique tags from note frontmatters in the vault.
---@param dir string|obsidian.Path
---@param callback fun(tags: string[])
M.get_vault_tags_async = function(dir, callback)
  local tags = {}
  local tx, rx = channel.oneshot()
  local Note = require "obsidian.note"
  local paths_seen = {}

  -- Use 'rg -l' to find files containing 'tags:' or 'tag:' efficiently.
  -- Catch both indented and start-of-line keys.
  local cmd = { "rg", "--no-config", "--type=md", "-l", "^\\s*tags?:", tostring(Path.new(dir):resolve()) }
  require("obsidian.async").run_job_async(cmd[1], { unpack(cmd, 2) }, function(path)
    path = path:match("^%s*(.-)%s*$")
    if path == "" or paths_seen[path] then return end
    paths_seen[path] = true

    local ok, note = pcall(Note.from_file, path, { max_lines = 50 })
    if ok and note and note.tags then
      for _, tag in ipairs(note.tags) do
        local normalized = tag:gsub("^#", ""):match("^%s*(.-)%s*$")
        if normalized ~= "" then
          tags[normalized] = true
        end
      end
    end
  end, function(_)
    tx()
  end)

  async.run(function()
    rx()
    local keys = vim.tbl_keys(tags)
    table.sort(keys)
    return keys
  end, callback)
end

M.get_stats_file = function()
  local d = vim.fn.stdpath("data") .. "/obsidian-srs"
  vim.fn.mkdir(d, "p")
  return d .. "/stats.json"
end

return M
