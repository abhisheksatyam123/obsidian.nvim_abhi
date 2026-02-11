--- Spaced Repetition System (SRS) module for obsidian.nvim
---
--- Card format (compatible with Obsidian Spaced Repetition community plugin):
---   Single-line basic:    Question::Answer
---   Single-line reversed: Question:::Answer
---   Scheduling data:      <!--SR:!2025-02-15,3,250-->
---
--- The SM-2 algorithm is used for scheduling.

local Path = require "obsidian.path"
local log = require "obsidian.log"
local search = require "obsidian.search"
local async = require "plenary.async"
local channel = require("plenary.async.control").channel

local M = {}

---@class obsidian.srs.Card
---@field question string
---@field answer string
---@field file_path string Absolute path to the file containing this card.
---@field line_num integer 1-indexed line number where the card starts.
---@field due_date string|? ISO date string "YYYY-MM-DD" or nil if new.
---@field interval integer Current interval in days (0 = new card).
---@field ease integer Ease factor * 100 (e.g. 250 = 2.50).
---@field is_new boolean True if the card has never been reviewed.
---@field is_reversed boolean True if this is a reversed card (answer shown first).
---@field raw_line string The raw line text from the file.

--- Default ease factor (2.5 * 100).
M.DEFAULT_EASE = 250

--- Minimum ease factor (1.3 * 100).
M.MIN_EASE = 130

--- Default initial interval (1 day).
M.DEFAULT_INTERVAL = 1

--- Regex patterns for ripgrep.
M.CARD_SEPARATOR_PATTERN = "::[:]{0,1}[^>]"

--- Pattern for finding cloze deletions {{c1::text}}
M.CLOZE_PATTERN = "\\{\\{c\\d+::"

--- Lua pattern to parse a single-line card: `Question :: Answer` or `Question ::: Answer`
---@param line string
---@return string|?, string|?, boolean is_reversed
M.parse_card_line = function(line)
  local q, a = string.match(line, "^(.-)%s*:::%s*(.+)$")
  if q and a then
    a = M.strip_schedule_comment(a)
    return q, a, true
  end

  q, a = string.match(line, "^(.-)%s*::%s*(.+)$")
  if q and a then
    a = M.strip_schedule_comment(a)
    return q, a, false
  end

  return nil, nil, false
end

--- Parse a cloze deletion card
--- Format: Text {{c1::hidden}} more text
---@param line string
---@return string|?, string|?, integer|?
M.parse_cloze_line = function(line)
  local clozes = {}
  local pattern = "{{c(%d+)::([^}]+)}}"

  for num, text in string.gmatch(line, pattern) do
    table.insert(clozes, { num = tonumber(num), text = text })
  end

  if #clozes == 0 then
    return nil
  end

  local question = line
  local answers = {}

  for _, cloze in ipairs(clozes) do
    question = string.gsub(question, "{{c" .. cloze.num .. "::[^}]+}}", "[...]", 1)
    table.insert(answers, cloze.text)
  end

  question = string.gsub(question, "{{c%d+::([^}]+)}}", "%1")

  return question, table.concat(answers, ", "), clozes[1].num
end

--- Extract tags from text
---@param text string
---@return string[]
M.extract_tags = function(text)
  local tags = {}
  for tag in string.gmatch(text, "#([%w_/-]+)") do
    table.insert(tags, tag)
  end
  return tags
end

--- Strip the scheduling HTML comment from the end of a string.
---@param s string
---@return string
M.strip_schedule_comment = function(s)
  local stripped = string.gsub(s, "%s*<!%-%-SR:!?[^%-]-%-%->{0,1}%s*$", "")
  stripped = string.gsub(stripped, "%s*<!%-%-SR:[^>]*%-%->%s*$", "")
  return stripped
end

--- Parse the scheduling comment from a line.
--- Format: <!--SR:!2025-02-15,3,250-->
---@param line string
---@return string|? due_date, integer|? interval, integer|? ease
M.parse_schedule_comment = function(line)
  local date, interval, ease = string.match(line, "<!%-%-SR:!([%d%-]+),(%d+),(%d+)%-%->")
  if date then
    return date, tonumber(interval), tonumber(ease)
  end
  return nil, nil, nil
end

--- Build a scheduling comment string.
---@param due_date string ISO date "YYYY-MM-DD"
---@param interval integer
---@param ease integer
---@return string
M.build_schedule_comment = function(due_date, interval, ease)
  return string.format("<!--SR:!%s,%d,%d-->", due_date, interval, ease)
end

--- SM-2 algorithm implementation.
---
--- Grade scale (0-5):
---   0 = Complete blackout
---   1 = Incorrect; correct answer remembered upon seeing it
---   2 = Incorrect; correct answer seemed easy to recall
---   3 = Correct with serious difficulty
---   4 = Correct with some hesitation
---   5 = Perfect response
---
--- For simplicity, we map to 4 buttons:
---   "again"  = grade 1 (reset)
---   "hard"   = grade 3
---   "good"   = grade 4
---   "easy"   = grade 5
---
---@param grade integer SM-2 grade (0-5)
---@param interval integer Current interval in days
---@param ease integer Current ease factor * 100 (e.g. 250 = 2.5)
---@return integer new_interval, integer new_ease
M.sm2 = function(grade, interval, ease)
  local new_ease = ease
  local new_interval = interval

  if grade < 3 then
    new_interval = 1
    new_ease = math.max(M.MIN_EASE, ease - 20)
  else
    if interval == 0 then
      new_interval = 1
    elseif interval == 1 then
      new_interval = 6
    else
      new_interval = math.ceil(interval * (ease / 100))
    end

    -- SM-2 ease adjustment: EF' = EF + (0.1 - (5-q) * (0.08 + (5-q) * 0.02))
    local delta = math.floor((0.1 - (5 - grade) * (0.08 + (5 - grade) * 0.02)) * 100)
    new_ease = math.max(M.MIN_EASE, ease + delta)
  end

  return new_interval, new_ease
end

--- Map a button name to an SM-2 grade.
---@param button string "again"|"hard"|"good"|"easy"
---@return integer
M.button_to_grade = function(button)
  local grades = {
    again = 1,
    hard = 3,
    good = 4,
    easy = 5,
  }
  return grades[button] or 4
end

--- Compute the next due date from today + interval days.
---@param interval integer Days from now.
---@return string ISO date "YYYY-MM-DD"
M.next_due_date = function(interval)
  local time = os.time() + (interval * 86400)
  return os.date("%Y-%m-%d", time)
end

--- Get today's date as ISO string.
---@return string
M.today = function()
  return os.date("%Y-%m-%d", os.time())
end

--- Check if a card is due (due_date <= today).
---@param due_date string|? ISO date or nil (new cards are always due).
---@return boolean
M.is_due = function(due_date)
  if due_date == nil then
    return true
  end
  return due_date <= M.today()
end

--- Calculate days until a card is due.
---@param due_date string|? ISO date or nil.
---@return integer
M.days_until_due = function(due_date)
  if due_date == nil then
    return 0
  end
  
  local today_time = os.time()
  local due_time = os.time({
    year = tonumber(due_date:sub(1, 4)),
    month = tonumber(due_date:sub(6, 7)),
    day = tonumber(due_date:sub(9, 10)),
  })
  
  local diff_days = math.floor(os.difftime(due_time, today_time) / 86400)
  return diff_days
end

--- Parse a card from a file line.
---@param line string
---@param file_path string
---@param line_num integer
---@return obsidian.srs.Card|?
M.card_from_line = function(line, file_path, line_num)
  local question, answer, is_reversed = M.parse_card_line(line)
  if not question or not answer then
    return nil
  end

  local due_date, interval, ease = M.parse_schedule_comment(line)

  return {
    question = question,
    answer = answer,
    file_path = file_path,
    line_num = line_num,
    due_date = due_date,
    interval = interval or 0,
    ease = ease or M.DEFAULT_EASE,
    is_new = (due_date == nil),
    is_reversed = is_reversed,
    raw_line = line,
  }
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

  if card.line_num > #lines then
    log.err("SRS card line number %d exceeds file length %d in %s", card.line_num, #lines, file_path)
    return false
  end

  local old_line = lines[card.line_num]

  local new_line = string.gsub(old_line, "%s*<!%-%-SR:[^>]*%-%->%s*$", "")
  new_line = new_line .. " " .. new_comment

  lines[card.line_num] = new_line

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
  card.raw_line = new_line

  log.info("Reviewed card: next due %s (interval=%d, ease=%d)", new_due, new_interval, new_ease)
  return true
end

--- Find all flashcards across the vault using ripgrep.
--- This uses the same pattern as `client:find_tags_async()`.
---
---@param dir string|obsidian.Path The vault root directory.
---@param callback fun(cards: obsidian.srs.Card[])
---@param opts { due_only: boolean|? }|?
M.find_cards_async = function(dir, callback, opts)
  opts = opts or {}

  ---@type obsidian.srs.Card[]
  local cards = {}

  local tx, rx = channel.oneshot()

  ---@param match_data MatchData
  local on_match = function(match_data)
    local path = Path.new(match_data.path.text):resolve({ strict = true })
    local line = match_data.lines.text
    line = string.gsub(line, "\n$", "")
    local card = M.card_from_line(line, tostring(path), match_data.line_number)
    if card then
      if opts.due_only then
        if M.is_due(card.due_date) then
          cards[#cards + 1] = card
        end
      else
        cards[#cards + 1] = card
      end
    end
  end

  search.search_async(dir, M.CARD_SEPARATOR_PATTERN, nil, on_match, function(_)
    tx()
  end)

  async.run(function()
    rx()
    return cards
  end, callback)
end

--- Statistics file path
M.get_stats_file = function()
  local data_dir = vim.fn.stdpath("data") .. "/obsidian-srs"
  vim.fn.mkdir(data_dir, "p")
  return data_dir .. "/stats.json"
end

--- Load review statistics
M.load_stats = function()
  local stats_file = M.get_stats_file()
  local f = io.open(stats_file, "r")
  if not f then
    return {
      total_reviews = 0,
      total_cards_created = 0,
      daily_stats = {},
      streak = 0,
      last_review_date = nil,
    }
  end

  local content = f:read("*all")
  f:close()

  local ok, stats = pcall(vim.json.decode, content)
  if not ok or not stats then
    return {
      total_reviews = 0,
      total_cards_created = 0,
      daily_stats = {},
      streak = 0,
      last_review_date = nil,
    }
  end

  return stats
end

--- Save review statistics
M.save_stats = function(stats)
  local stats_file = M.get_stats_file()
  local f = io.open(stats_file, "w")
  if not f then
    log.err("Failed to save SRS stats")
    return
  end

  f:write(vim.json.encode(stats))
  f:close()
end

--- Update statistics after a review
M.update_stats = function(cards_reviewed, new_cards_reviewed)
  local stats = M.load_stats()
  local today = M.today()

  if not stats.daily_stats[today] then
    stats.daily_stats[today] = {
      reviews = 0,
      new_cards = 0,
    }
  end

  stats.daily_stats[today].reviews = stats.daily_stats[today].reviews + cards_reviewed
  stats.daily_stats[today].new_cards = stats.daily_stats[today].new_cards + (new_cards_reviewed or 0)
  stats.total_reviews = stats.total_reviews + cards_reviewed

  if stats.last_review_date then
    local last_time = os.time({
      year = tonumber(stats.last_review_date:sub(1, 4)),
      month = tonumber(stats.last_review_date:sub(6, 7)),
      day = tonumber(stats.last_review_date:sub(9, 10)),
    })
    local today_time = os.time()
    local diff_days = os.difftime(today_time, last_time) / 86400

    if diff_days >= 2 then
      stats.streak = 1
    elseif stats.last_review_date ~= today then
      stats.streak = stats.streak + 1
    end
  else
    stats.streak = 1
  end

  stats.last_review_date = today
  M.save_stats(stats)

  return stats
end

--- Get review statistics summary
M.get_stats_summary = function()
  local stats = M.load_stats()
  local today = M.today()
  local today_stats = stats.daily_stats[today] or { reviews = 0, new_cards = 0 }

  return {
    total_reviews = stats.total_reviews,
    today_reviews = today_stats.reviews,
    today_new_cards = today_stats.new_cards,
    streak = stats.streak,
    last_review_date = stats.last_review_date,
  }
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
    local card_tags = M.extract_tags(card.question .. " " .. card.answer)
    for _, card_tag in ipairs(card_tags) do
      if tag_set[card_tag] then
        table.insert(filtered, card)
        break
      end
    end
  end

  return filtered
end

--- Apply review limits from config
M.apply_review_limits = function(cards, config)
  config = config or {}
  local max_new = config.max_new_per_day or 20
  local max_total = config.max_reviews_per_day or 100

  local stats = M.load_stats()
  local today = M.today()
  local today_stats = stats.daily_stats[today] or { reviews = 0, new_cards = 0 }

  local new_count = today_stats.new_cards or 0
  local total_count = today_stats.reviews or 0

  local filtered = {}
  for _, card in ipairs(cards) do
    if total_count >= max_total then
      break
    end

    if card.is_new then
      if new_count >= max_new then
        goto continue
      end
      new_count = new_count + 1
    end

    table.insert(filtered, card)
    total_count = total_count + 1

    ::continue::
  end

  return filtered
end

--- Get upcoming reviews for the next N days
M.get_upcoming_reviews = function(cards, days)
  days = days or 7
  local upcoming = {}

  for i = 0, days do
    local date = os.date("%Y-%m-%d", os.time() + (i * 86400))
    upcoming[date] = 0
  end

  for _, card in ipairs(cards) do
    if card.due_date and upcoming[card.due_date] then
      upcoming[card.due_date] = upcoming[card.due_date] + 1
    end
  end

  return upcoming
end

--- Find cloze deletion cards
M.find_cloze_cards_async = function(dir, callback, opts)
  opts = opts or {}

  local cards = {}
  local tx, rx = channel.oneshot()

  local on_match = function(match_data)
    local path = Path.new(match_data.path.text):resolve({ strict = true })
    local line = match_data.lines.text
    line = string.gsub(line, "\n$", "")

    local cloze_q, cloze_a, cloze_num = M.parse_cloze_line(line)
    if cloze_q and cloze_a then
      local due_date, interval, ease = M.parse_schedule_comment(line)
      local card = {
        question = cloze_q,
        answer = cloze_a,
        file_path = tostring(path),
        line_num = match_data.line_number,
        due_date = due_date,
        interval = interval or 0,
        ease = ease or M.DEFAULT_EASE,
        is_new = (due_date == nil),
        is_reversed = false,
        is_cloze = true,
        cloze_num = cloze_num,
        raw_line = line,
        tags = M.extract_tags(line),
      }

      if opts.due_only then
        if M.is_due(card.due_date) then
          cards[#cards + 1] = card
        end
      else
        cards[#cards + 1] = card
      end
    end
  end

  search.search_async(dir, M.CLOZE_PATTERN, nil, on_match, function(_)
    tx()
  end)

  async.run(function()
    rx()
    return cards
  end, callback)
end

return M
