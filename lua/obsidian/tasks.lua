local log = require "obsidian.log"
local Job = require "plenary.job"
local Path = require "obsidian.path"

local M = {}

-- Debouncing for task toggles to prevent double-triggers
M._last_toggle_cache = {
  time = 0,
  bufnr = nil,
  lnum = nil,
}

--- Task state characters.
---@enum obsidian.TaskState
M.states = {
  TODO = " ",
  ACTIVE = "/",
  PAUSED = "|",
  BLOCKED = "?",
  CANCELLED = "-",
  DONE = "x",
}

--- Human-readable state names.
M.state_names = {
  [" "] = "Todo",
  ["/"] = "Active",
  ["|"] = "Paused",
  ["?"] = "Blocked",
  ["-"] = "Cancelled",
  ["x"] = "Done",
}

--- Icons used in time log blockquotes.
M.state_icons = {
  ["/"] = "🟢",
  ["|"] = "⏸",
  ["?"] = "🚧",
  ["-"] = "❌",
  ["x"] = "✅",
  ["switch"] = "🔄",
}

---------------------------------------------------------------------------
-- Parsing
---------------------------------------------------------------------------

---@class obsidian.TaskInfo
---@field lnum integer 0-based line number
---@field indent integer number of leading whitespace characters
---@field state string single-character state inside the checkbox
---@field text string task text after the checkbox marker
---@field full_line string the original full line
---@field priority integer|nil 1, 2, or 3
---@field deferred boolean

--- Parse a task/checkbox line into its components.
---@param line string
---@param lnum integer 0-based line number
---@return obsidian.TaskInfo|nil
M.parse_task_line = function(line, lnum)
  local indent_str, state, text = string.match(line, "^(%s*)%- %[(.)]%s*(.*)")
  if not state then
    return nil
  end

  local priority = nil
  if string.find(text, "#p1") then
    priority = 1
  elseif string.find(text, "#p2") then
    priority = 2
  elseif string.find(text, "#p3") then
    priority = 3
  end

  local deferred = string.find(text, "#deferred") ~= nil

  return {
    lnum = lnum,
    indent = #indent_str,
    state = state,
    text = text,
    full_line = line,
    priority = priority,
    deferred = deferred,
  }
end

---------------------------------------------------------------------------
-- Time helpers
---------------------------------------------------------------------------

--- Format an os.time() value as "YYYY-MM-DD HH:MM".
---@param time integer|nil defaults to os.time()
---@return string
M.format_timestamp = function(time)
  time = time or os.time()
  return os.date("%Y-%m-%d %H:%M", time)
end

--- Parse a "YYYY-MM-DD HH:MM" string back to os.time().
---@param str string
---@return integer|nil
M.parse_timestamp = function(str)
  local year, month, day, hour, min = string.match(str, "(%d+)-(%d+)-(%d+)%s+(%d+):(%d+)")
  if not year then
    return nil
  end
  return os.time {
    year = tonumber(year),
    month = tonumber(month),
    day = tonumber(day),
    hour = tonumber(hour),
    min = tonumber(min),
    sec = 0,
  }
end

--- Calculate duration in minutes between two epoch timestamps.
---@param start_time integer
---@param end_time integer
---@return integer
M.calc_duration_minutes = function(start_time, end_time)
  return math.max(0, math.floor((end_time - start_time) / 60))
end

--- Format a minute count as a human-readable string ("45m", "1h30m", "2h").
---@param minutes integer
---@return string
M.format_duration = function(minutes)
  if minutes < 60 then
    return string.format("%dm", minutes)
  end
  local hours = math.floor(minutes / 60)
  local rem = minutes % 60
  if rem == 0 then
    return string.format("%dh", hours)
  end
  return string.format("%dh%dm", hours, rem)
end

---------------------------------------------------------------------------
-- Time-log helpers (blockquote lines below a task)
---------------------------------------------------------------------------

--- Collect the blockquote time-log lines that sit directly below a task.
---@param bufnr integer
---@param task_lnum integer 0-based
---@return { line: string, lnum: integer }[]
M.get_time_logs = function(bufnr, task_lnum)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local task_line = lines[task_lnum + 1]
  if not task_line then
    return {}
  end

  local task_indent = #(string.match(task_line, "^(%s*)") or "")
  local logs = {}

  for i = task_lnum + 2, #lines do
    local line = lines[i]
    if not line then
      break
    end
    local line_indent = #(string.match(line, "^(%s*)") or "")
    if line_indent > task_indent and string.match(line, "^%s*>") then
      logs[#logs + 1] = { line = line, lnum = i - 1 }
    else
      break
    end
  end

  return logs
end

--- Collect time-log lines from a raw table of file lines (for file-based ops).
---@param file_lines string[] 1-based
---@param task_lnum_1 integer 1-based line number
---@param task_indent integer
---@return { line: string, lnum: integer }[]
M.get_time_logs_from_lines = function(file_lines, task_lnum_1, task_indent)
  local logs = {}
  for i = task_lnum_1 + 1, #file_lines do
    local line = file_lines[i]
    if not line then
      break
    end
    local li = #(string.match(line, "^(%s*)") or "")
    if li > task_indent and string.match(line, "^%s*>") then
      logs[#logs + 1] = { line = line, lnum = i - 1 }
    else
      break
    end
  end
  return logs
end

--- Walk backwards through the logs to find the most recent "Started" or "Resumed" timestamp.
---@param logs { line: string, lnum: integer }[]
---@return integer|nil epoch
M.find_last_start_time = function(logs)
  for i = #logs, 1, -1 do
    local ts_str = string.match(logs[i].line, "Started:%s*(.+)$")
      or string.match(logs[i].line, "Resumed:%s*(.+)$")
    if ts_str then
      return M.parse_timestamp(ts_str)
    end
  end
  return nil
end

--- Sum all "(Duration: …)" entries from existing logs.
---@param logs { line: string, lnum: integer }[]
---@return integer total_minutes
M.calc_total_time = function(logs)
  local total = 0
  for _, entry in ipairs(logs) do
    local h, m = string.match(entry.line, "Duration:%s*(%d+)h(%d+)m")
    if h then
      total = total + tonumber(h) * 60 + tonumber(m)
    else
      local hours_only = string.match(entry.line, "Duration:%s*(%d+)h[^%d]")
        or string.match(entry.line, "Duration:%s*(%d+)h$")
      if hours_only then
        total = total + tonumber(hours_only) * 60
      else
        local mins_only = string.match(entry.line, "Duration:%s*(%d+)m")
        if mins_only then
          total = total + tonumber(mins_only)
        end
      end
    end
  end
  return total
end

--- Insert a time-log blockquote line after the task and its existing logs.
---@param bufnr integer
---@param task_lnum integer 0-based
---@param entry string log text (without the "> " prefix)
---@param task_indent integer
M.inject_time_log = function(bufnr, task_lnum, entry, task_indent)
  local logs = M.get_time_logs(bufnr, task_lnum)
  
  -- Deduplication: Don't add the exact same log twice in a row for the same task.
  if #logs > 0 then
    local last_log = logs[#logs].line
    if string.find(last_log, entry, 1, true) then
      return
    end
  end

  local insert_at = task_lnum + 1 + #logs
  local indent = string.rep(" ", task_indent + 2)
  local log_line = indent .. "> " .. entry
  vim.api.nvim_buf_set_lines(bufnr, insert_at, insert_at, false, { log_line })
end

---------------------------------------------------------------------------
-- Low-level state mutation
---------------------------------------------------------------------------

--- Swap the state character in a task line inside a buffer.
---@param bufnr integer
---@param lnum integer 0-based
---@param new_state string single character
M.set_task_state = function(bufnr, lnum, new_state)
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]
  if not line then
    return
  end
  local new_line = string.gsub(line, "^(%s*%- %[).(%])", "%1" .. new_state .. "%2", 1)
  vim.api.nvim_buf_set_lines(bufnr, lnum, lnum + 1, false, { new_line })
end

---------------------------------------------------------------------------
-- Priority & Deferral Management
---------------------------------------------------------------------------

--- Update priority tags on a task.
---@param bufnr integer
---@param lnum integer 0-based
---@param p_level integer|nil 1, 2, 3 or nil to remove
M.set_priority = function(bufnr, lnum, p_level)
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]
  if not line then
    return
  end
  local task = M.parse_task_line(line, lnum)
  if not task then
    return
  end

  -- Remove existing priority tags.
  local new_text = string.gsub(task.text, "%s*#p[123]", "")

  -- Add new tag if specified.
  if p_level and p_level >= 1 and p_level <= 3 then
    new_text = new_text .. " #p" .. p_level
  end

  local indent_str = string.rep(" ", task.indent)
  local new_line = string.format("%s- [%s] %s", indent_str, task.state, new_text)
  vim.api.nvim_buf_set_lines(bufnr, lnum, lnum + 1, false, { new_line })
end

--- Defer a task (move to not important).
---@param bufnr integer
---@param lnum integer 0-based
M.defer_task = function(bufnr, lnum)
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]
  if not line then
    return
  end
  local task = M.parse_task_line(line, lnum)
  if not task then
    return
  end

  -- Remove priorities and add #deferred.
  local new_text = string.gsub(task.text, "%s*#p[123]", "")
  if not string.find(new_text, "#deferred") then
    new_text = new_text .. " #deferred"
  end

  local indent_str = string.rep(" ", task.indent)
  -- Mark as cancelled [-] or a custom deferred state.
  local new_line = string.format("%s- [-] %s", indent_str, new_text)
  vim.api.nvim_buf_set_lines(bufnr, lnum, lnum + 1, false, { new_line })

  local timestamp = M.format_timestamp()
  M.inject_time_log(bufnr, lnum, "💤 Deferred: " .. timestamp, task.indent)
end

---------------------------------------------------------------------------
-- Internal Helpers
---------------------------------------------------------------------------

--- Calculate transition log entry with duration math.
---@param bufnr integer|nil dummy if using raw lines
---@param task obsidian.TaskInfo
---@param new_state string
---@param now integer
---@param reason string|nil "manual", "context_switch", "auto"
---@param current_lines string[]|nil optional raw lines
---@return string|nil
M._get_log_entry = function(bufnr, task, new_state, now, reason, current_lines)
  local timestamp = M.format_timestamp(now)
  local icon = M.state_icons[new_state]
  local logs = current_lines and M.get_time_logs_from_lines(current_lines, task.lnum + 1, task.indent) 
                or M.get_time_logs(bufnr, task.lnum)

  if new_state == "/" then
    local verb = task.state == " " and "Started" or "Resumed"
    return icon .. " " .. verb .. ": " .. timestamp
  elseif new_state == "|" then
    local verb = reason == "context_switch" and "Context Switched" or "Paused"
    local start_time = M.find_last_start_time(logs)
    local duration = ""
    if start_time then
      duration = " (Duration: " .. M.format_duration(M.calc_duration_minutes(start_time, now)) .. ")"
    end
    local log_icon = reason == "context_switch" and M.state_icons["switch"] or icon
    return log_icon .. " " .. verb .. ": " .. timestamp .. duration
  elseif new_state == "x" then
    local start_time = M.find_last_start_time(logs)
    local total_mins = M.calc_total_time(logs)
    local info = ""
    if start_time then
      local sess = M.calc_duration_minutes(start_time, now)
      info = string.format(" (Session: %s, Total: %s)", M.format_duration(sess), M.format_duration(total_mins + sess))
    elseif total_mins > 0 then
      info = string.format(" (Total: %s)", M.format_duration(total_mins))
    end
    local verb = reason == "auto" and "Done (auto)" or "Done"
    return icon .. " " .. verb .. ": " .. timestamp .. info
  elseif new_state == "?" then
    local start_time = M.find_last_start_time(logs)
    local duration = ""
    if start_time then
      duration = " (Duration: " .. M.format_duration(M.calc_duration_minutes(start_time, now)) .. ")"
    end
    return icon .. " Blocked: " .. timestamp .. duration
  elseif new_state == "-" then
    local start_time = M.find_last_start_time(logs)
    local duration = ""
    if start_time then
      duration = " (Duration: " .. M.format_duration(M.calc_duration_minutes(start_time, now)) .. ")"
    end
    return icon .. " Cancelled: " .. timestamp .. duration
  elseif new_state == " " and (task.state == "x" or task.state == "-") then
    return "🔄 Reopened: " .. timestamp
  end

  return nil
end

--- Internal helper to apply a state change and inject log.
---@param bufnr integer
---@param lnum integer 0-based
---@param new_state string
---@param reason string|nil
M._apply_state_change = function(bufnr, lnum, new_state, reason)
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]
  if not line then return end
  local task = M.parse_task_line(line, lnum)
  if not task or task.state == new_state then return end

  local now = os.time()
  local log_entry = M._get_log_entry(bufnr, task, new_state, now, reason)

  M.set_task_state(bufnr, lnum, new_state)
  if log_entry then
    M.inject_time_log(bufnr, lnum, log_entry, task.indent)
  end

  if new_state == "x" then
    M.recursive_check_parent(bufnr, lnum)
  end
end

---------------------------------------------------------------------------
-- Smart toggle (context-aware state machine)
---------------------------------------------------------------------------

--- The primary toggle command.
--- Consolidates all state changes for the current buffer into a single atomic pass.
---@param bufnr integer
---@param lnum integer 0-based
M.smart_toggle = function(bufnr, lnum)
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]
  if not line then return end

  local target_task = M.parse_task_line(line, lnum)

  -- Convert plain line to task if needed.
  if not target_task then
    local list_indent, list_rest = string.match(line, "^(%s*%- )(.*)")
    if list_indent then
      vim.api.nvim_buf_set_lines(bufnr, lnum, lnum + 1, false, { list_indent .. "[ ] " .. list_rest })
    else
      local text_indent, text = string.match(line, "^(%s*)(.*)")
      if text and text ~= "" then
        vim.api.nvim_buf_set_lines(bufnr, lnum, lnum + 1, false, { (text_indent or "") .. "- [ ] " .. text })
      end
    end
    return
  end

  -- 1. DEBOUNCING
  local now = os.time()
  if M._last_toggle_cache.bufnr == bufnr and M._last_toggle_cache.lnum == lnum and (now - M._last_toggle_cache.time) < 1 then
    return
  end
  M._last_toggle_cache = { time = now, bufnr = bufnr, lnum = lnum }

  -- 2. DETERMINE NEW STATE
  local new_state
  if target_task.state == "/" then new_state = "|"
  elseif target_task.state == "-" or target_task.state == "x" then new_state = " "
  else new_state = "/" end

  -- 3. ATOMIC BUFFER PROCESSING
  local buffer_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local changes = {}

  if new_state == "/" then
    for i, l in ipairs(buffer_lines) do
      local t = M.parse_task_line(l, i - 1)
      if t and t.state == "/" and i - 1 ~= lnum then
        local entry = M._get_log_entry(bufnr, t, "|", now, "context_switch", buffer_lines)
        local updated_line = string.gsub(l, "^(%s*%- %[)/(%])", "%1|%2", 1)
        local logs = M.get_time_logs_from_lines(buffer_lines, i, t.indent)
        local indent = string.rep(" ", t.indent + 2)
        table.insert(changes, { lnum = i - 1, line = updated_line, log = indent .. "> " .. entry, log_at = i + #logs })
      end
    end

    -- 4. VAULT-WIDE PROCESSING (excluding current buffer)
    local client = require("obsidian").get_client()
    M.pause_all_active(tostring(client.dir), nil, "context_switch", nil, true, bufnr)
  end

  -- 5. TARGET TASK CHANGE
  local log_entry = M._get_log_entry(bufnr, target_task, new_state, now, "manual", buffer_lines)
  local target_logs = M.get_time_logs_from_lines(buffer_lines, lnum + 1, target_task.indent)
  table.insert(changes, { 
    lnum = lnum, 
    line = string.gsub(buffer_lines[lnum + 1], "^(%s*%- %[).(%])", "%1" .. new_state .. "%2", 1),
    log = log_entry and (string.rep(" ", target_task.indent + 2) .. "> " .. log_entry) or nil,
    log_at = lnum + 1 + #target_logs
  })

  -- Sort descending to keep indices stable.
  table.sort(changes, function(a, b) return a.lnum > b.lnum end)

  for _, c in ipairs(changes) do
    vim.api.nvim_buf_set_lines(bufnr, c.lnum, c.lnum + 1, false, { c.line })
    if c.log then
      local next_l = vim.api.nvim_buf_get_lines(bufnr, c.log_at, c.log_at + 1, false)[1]
      if next_l ~= c.log then
        vim.api.nvim_buf_set_lines(bufnr, c.log_at, c.log_at, false, { c.log })
      end
    end
  end
end

---------------------------------------------------------------------------
-- Direct state commands
---------------------------------------------------------------------------

--- Mark a task as done.
---@param bufnr integer
---@param lnum integer 0-based
M.mark_done = function(bufnr, lnum)
  M._apply_state_change(bufnr, lnum, "x", "manual")
end

--- Mark a task as blocked.
---@param bufnr integer
---@param lnum integer 0-based
M.mark_blocked = function(bufnr, lnum)
  M._apply_state_change(bufnr, lnum, "?", "manual")
end

--- Mark a task as cancelled.
---@param bufnr integer
---@param lnum integer 0-based
M.mark_cancelled = function(bufnr, lnum)
  M._apply_state_change(bufnr, lnum, "-", "manual")
end

---------------------------------------------------------------------------
-- Recursive subtask completion
---------------------------------------------------------------------------

--- Find the parent task of a given subtask (by walking upward).
---@param bufnr integer
---@param lnum integer 0-based
---@return obsidian.TaskInfo|nil
M.find_parent_task = function(bufnr, lnum)
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]
  if not line then return nil end
  local task = M.parse_task_line(line, lnum)
  if not task or task.indent == 0 then return nil end

  for i = lnum - 1, 0, -1 do
    local prev_line = vim.api.nvim_buf_get_lines(bufnr, i, i + 1, false)[1]
    if not prev_line then break end
    if string.match(prev_line, "^%s*>") then goto continue end
    local prev_task = M.parse_task_line(prev_line, i)
    if prev_task and prev_task.indent < task.indent then return prev_task end
    local prev_indent = #(string.match(prev_line, "^(%s*)") or "")
    if prev_indent < task.indent and not prev_task then break end
    ::continue::
  end
  return nil
end

--- Find all direct subtasks below a parent task.
---@param bufnr integer
---@param parent_lnum integer 0-based
---@param parent_indent integer
---@return obsidian.TaskInfo[]
M.find_subtasks = function(bufnr, parent_lnum, parent_indent)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local subtasks = {}
  local child_indent = nil

  for i = parent_lnum + 2, #lines do
    local line = lines[i]
    if not line or line == "" then goto continue end
    if string.match(line, "^%s*>") then goto continue end
    local line_indent = #(string.match(line, "^(%s*)") or "")
    if line_indent <= parent_indent then break end
    local t = M.parse_task_line(line, i - 1)
    if t then
      if child_indent == nil then child_indent = t.indent end
      if t.indent == child_indent then subtasks[#subtasks + 1] = t end
    end
    ::continue::
  end
  return subtasks
end

--- If all direct subtasks of a parent are done, auto-complete the parent and recurse upward.
---@param bufnr integer
---@param child_lnum integer 0-based
M.recursive_check_parent = function(bufnr, child_lnum)
  local parent = M.find_parent_task(bufnr, child_lnum)
  if not parent then return end

  local subtasks = M.find_subtasks(bufnr, parent.lnum, parent.indent)
  if #subtasks == 0 then return end

  for _, st in ipairs(subtasks) do
    local cur = vim.api.nvim_buf_get_lines(bufnr, st.lnum, st.lnum + 1, false)[1]
    local ct = M.parse_task_line(cur, st.lnum)
    if not ct or ct.state ~= "x" then return end
  end

  if parent.state ~= "x" then
    M._apply_state_change(bufnr, parent.lnum, "x", "auto")
  end
end

---------------------------------------------------------------------------
-- Vault-wide operations (ripgrep)
---------------------------------------------------------------------------

--- Find all active [/] tasks across the vault using ripgrep.
---@param vault_root string
---@param callback fun(results: {file: string, lnum: integer, line: string}[])
---@param sync boolean|nil
M.find_active_tasks_rg = function(vault_root, callback, sync)
  local results = {}
  local job = Job:new {
    command = "rg",
    args = { "--line-number", "--no-heading", "--type", "md", "-e", "^\\s*- \\[/\\]", vault_root },
    on_stdout = function(_, line)
      if line and line ~= "" then
        local file, lnum, content = string.match(line, "^(.+):(%d+):(.+)$")
        if file then table.insert(results, { file = file, lnum = tonumber(lnum), line = content }) end
      end
    end,
  }
  if sync then job:sync() callback(results)
  else job.on_exit = function() vim.schedule(function() callback(results) end) end job:start() end
end

--- Internal helper to process a single loaded buffer for active tasks.
---@param bufnr integer
---@param vault_root string resolved
---@param exclude_file string|nil resolved
---@param exclude_lnum integer|nil 1-based
---@param now integer
---@return integer count, integer offset
M._pause_active_in_buffer = function(bufnr, vault_root, exclude_file, exclude_lnum, now)
  local buf_path = vim.api.nvim_buf_get_name(bufnr)
  if buf_path == "" then return 0, 0 end
  local resolved_path = Path.new(buf_path):resolve().filename
  if not vim.startswith(resolved_path, vault_root) then return 0, 0 end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local tasks_to_pause = {}
  for i, line in ipairs(lines) do
    local t = M.parse_task_line(line, i - 1)
    if t and t.state == "/" and not (exclude_file == resolved_path and exclude_lnum == i) then
      table.insert(tasks_to_pause, t)
    end
  end

  if #tasks_to_pause == 0 then return 0, 0 end
  local count, offset = 0, 0
  table.sort(tasks_to_pause, function(a, b) return a.lnum > b.lnum end)

  for _, t in ipairs(tasks_to_pause) do
    local idx = t.lnum + 1
    local entry = M._get_log_entry(bufnr, t, "|", now, "context_switch", lines)
    lines[idx] = string.gsub(lines[idx], "^(%s*%- %[)/(%])", "%1|%2", 1)
    local logs = M.get_time_logs_from_lines(lines, idx, t.indent)
    table.insert(lines, idx + #logs + 1, string.rep(" ", t.indent + 2) .. "> " .. entry)
    if exclude_file == resolved_path and idx < (exclude_lnum or 0) then offset = offset + 1 end
    count = count + 1
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return count, offset
end

--- Pause every active task in the vault.
---@param vault_root string
---@param callback fun(count: integer)|nil
---@param reason string|nil
---@param exclude table|nil { file: string, lnum: integer } (1-based lnum)
---@param sync boolean|nil
---@param exclude_bufnr integer|nil
---@return integer count, integer offset
M.pause_all_active = function(vault_root, callback, reason, exclude, sync, exclude_bufnr)
  local now = os.time()
  local total_count, total_offset = 0, 0
  local handled_files = {}
  local resolved_root = Path.new(vault_root):resolve().filename
  local exclude_file = (exclude and exclude.file) and Path.new(exclude.file):resolve().filename or nil

  if exclude_bufnr then
    local path = vim.api.nvim_buf_get_name(exclude_bufnr)
    if path ~= "" then exclude_file = Path.new(path):resolve().filename end
  end

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and bufnr ~= exclude_bufnr then
      local c, o = M._pause_active_in_buffer(bufnr, resolved_root, exclude_file, exclude and exclude.lnum, now)
      if c > 0 then
        total_count, total_offset = total_count + c, total_offset + o
        handled_files[Path.new(vim.api.nvim_buf_get_name(bufnr)):resolve().filename] = true
      end
    end
  end

  M.find_active_tasks_rg(vault_root, function(results)
    for _, result in ipairs(results) do
      local r_path = Path.new(result.file):resolve().filename
      if not handled_files[r_path] and r_path ~= exclude_file then
        local file_lines = {}
        local f = io.open(result.file, "r")
        if f then
          for line in f:lines() do table.insert(file_lines, line) end f:close()
          local t = M.parse_task_line(file_lines[result.lnum], result.lnum - 1)
          if t and t.state == "/" then
            file_lines[result.lnum] = string.gsub(file_lines[result.lnum], "^(%s*%- %[)/(%])", "%1|%2", 1)
            local logs = M.get_time_logs_from_lines(file_lines, result.lnum, t.indent)
            local entry = M._get_log_entry(nil, t, "|", now, "context_switch", file_lines)
            table.insert(file_lines, result.lnum + #logs + 1, string.rep(" ", t.indent + 2) .. "> " .. entry)
            local wf = io.open(result.file, "w")
            if wf then wf:write(table.concat(file_lines, "\n") .. "\n") wf:close() total_count = total_count + 1 end
          end
        end
      end
    end
    if not sync then vim.cmd "checktime" end
    if callback then callback(total_count)
    elseif total_count > 0 then
      if reason == "context_switch" then log.info("Context switched. Paused %d other active task(s)", total_count)
      elseif reason == "exit" then print(string.format("Obsidian: Auto-paused %d active task(s)", total_count))
      else log.info("Paused %d active task(s)", total_count) end
    end
  end, sync)
  return total_count, total_offset
end

---------------------------------------------------------------------------
-- Aggregation for dashboard
---------------------------------------------------------------------------

--- Aggregate all tasks across the vault grouped by priority and state.
---@param vault_root string
---@param opts { stale_threshold_days: integer|nil }|nil
---@param callback fun(tasks: table)
M.aggregate_tasks = function(vault_root, opts, callback)
  opts = opts or {}
  local stale_days = opts.stale_threshold_days or 3
  local all_tasks = { p1={}, p2={}, p3={}, active={}, paused={}, blocked={}, todo={}, done={}, cancelled={}, deferred={}, starving={} }

  Job:new({
    command = "rg",
    args = { "--line-number", "--no-heading", "--type", "md", "-e", "^\\s*- \\[[ /|?x-]\\]", vault_root },
    on_stdout = function(_, line)
      if not line or line == "" then return end
      local file, lnum, content = string.match(line, "^(.+):(%d+):(.+)$")
      if not file then return end
      local task = M.parse_task_line(content, tonumber(lnum) - 1)
      if not task then return end
      local entry = { file = file, lnum = task.lnum + 1, line = content, state = task.state, priority = task.priority, deferred = task.deferred, display_file = string.gsub(file, "^" .. vim.pesc(vault_root) .. "/?", "") }

      if task.state == "x" then table.insert(all_tasks.done, entry)
      elseif task.deferred then table.insert(all_tasks.deferred, entry)
      elseif task.state == "-" then table.insert(all_tasks.cancelled, entry)
      else
        if task.priority == 1 then table.insert(all_tasks.p1, entry)
        elseif task.priority == 2 then table.insert(all_tasks.p2, entry)
        elseif task.priority == 3 then table.insert(all_tasks.p3, entry) end
        if task.state == "/" then table.insert(all_tasks.active, entry)
        elseif task.state == "|" then table.insert(all_tasks.paused, entry)
        elseif task.state == "?" then table.insert(all_tasks.blocked, entry)
        elseif task.state == " " then table.insert(all_tasks.todo, entry) end
      end
    end,
    on_exit = function()
      vim.schedule(function()
        local threshold = os.time() - (stale_days * 24 * 60 * 60)
        local seen_files = {}
        for _, cat in ipairs { "p1", "p2", "active", "todo", "paused", "blocked" } do
          for _, task in ipairs(all_tasks[cat]) do
            if not seen_files[task.file] then
              seen_files[task.file] = true
              local stat = vim.loop.fs_stat(task.file)
              if stat and stat.mtime.sec < threshold then
                table.insert(all_tasks.starving, { file = task.file, display_file = task.display_file, last_modified = os.date("%Y-%m-%d", stat.mtime.sec), days_stale = math.floor((os.time() - stat.mtime.sec) / (24 * 60 * 60)) })
              end
            end
          end
        end
        callback(all_tasks)
      end)
    end,
  }):start()
end

return M
