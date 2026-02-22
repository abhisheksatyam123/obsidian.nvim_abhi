local Job = require "plenary.job"
local tasks = require "obsidian.tasks"
local log = require "obsidian.log"

local M = {}

--- Parse duration string like "(Duration: 1h45m)" into minutes.
---@param str string
---@return integer
M.parse_duration_to_minutes = function(str)
  local h = string.match(str, "Duration:%s*(%d+)h")
  local m = string.match(str, "Duration:.-(%d+)m")
  
  if not h and not m then
    -- Fallback for cases where "Duration: " might be followed by just digits and m/h
    h = string.match(str, "(%d+)h")
    m = string.match(str, "(%d+)m")
  end

  local total = 0
  if h then total = total + tonumber(h) * 60 end
  if m then total = total + tonumber(m) end
  return total
end

--- Get the target date for a buffer (filename or today).
---@param bufnr integer
---@return string
M.get_buffer_date = function(bufnr)
  local bufname = vim.api.nvim_buf_get_name(bufnr)
  local date_from_file = string.match(bufname, "(%d%d%d%d%-%d%d%-%d%d)")
  return date_from_file or os.date("%Y-%m-%d")
end

--- Refresh the statistics block in a buffer if the placeholder exists.
---@param client obsidian.Client
---@param bufnr integer
M.refresh_placeholder_in_buffer = function(client, bufnr)
  local placeholder = client.opts.tasks.daily_stats_placeholder
  if not placeholder or placeholder == "" then return end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for i, line in ipairs(lines) do
    if string.find(line, placeholder, 1, true) then
      local target_date = M.get_buffer_date(bufnr)
      local stats_result = nil
      
      M.get_daily_stats(tostring(client.dir), target_date, function(s)
        stats_result = s
      end, true)
      
      if stats_result then
        local report = M.format_report(stats_result, target_date)
        
        -- Find existing block to replace
        local replace_end = i
        local end_marker = "<!-- obsidian-task-stats-end -->"
        for k = i + 1, math.min(i + 50, #lines) do
          if string.find(lines[k], end_marker, 1, true) then
            replace_end = k
            break
          end
        end
        
        -- Fallback for legacy blocks
        if replace_end == i then
          for k = i + 1, math.min(i + 20, #lines) do
            if string.find(lines[k], "### 📊 Work Summary", 1, true) 
               or string.find(lines[k], "^  - %[.%]", 1) 
               or string.find(lines[k], "^%- %*.*%*", 1) then
              replace_end = k
            else
              break
            end
          end
        end
        
        vim.api.nvim_buf_set_lines(bufnr, i, replace_end, false, report)
      end
      break
    end
  end
end

--- Find work done on a specific date.
---@param vault_root string
---@param date_str string YYYY-MM-DD
---@param callback fun(stats: table)
---@param sync boolean|nil
M.get_daily_stats = function(vault_root, date_str, callback, sync)
  local stats = {
    total_minutes = 0,
    tasks = {}, -- name -> { minutes, state }
  }

  -- rg pattern: Find the date string followed by a Duration. 
  -- We use -B 5 to get the task checkbox above the log line.
  local job = Job:new({
    command = "rg",
    args = {
      "--line-number",
      "--no-heading",
      "--type",
      "md",
      "-B", "5",
      "-e", date_str .. ".*Duration: ",
      vault_root,
    },
    on_stdout = function(_, line)
      if line == "--" then
        stats._last_task = nil
        return
      end

      local file, type, lnum, content = string.match(line, "^(.-)([:-])(%d+)[:-](.*)$")
      if not file then return end

      if type == ":" then
        -- This is the match line (the log entry)
        local mins = M.parse_duration_to_minutes(content)
        stats.total_minutes = stats.total_minutes + mins
        
        -- We need to associate this with the task found in the context lines above it.
        if stats._last_task and stats._last_task.file == file then
          local task_name = stats._last_task.name
          if not stats.tasks[task_name] then
            stats.tasks[task_name] = { minutes = 0, state = stats._last_task.state }
          end
          stats.tasks[task_name].minutes = stats.tasks[task_name].minutes + mins
        end
      else
        -- This is a context line (-)
        local task = tasks.parse_task_line(content, tonumber(lnum) - 1)
        if task then
          stats._last_task = {
            file = file,
            name = task.text,
            state = task.state
          }
        end
      end
    end,
  })

  if sync then
    job:sync()
    stats._last_task = nil
    callback(stats)
  else
    job.on_exit = function()
      stats._last_task = nil
      vim.schedule(function()
        callback(stats)
      end)
    end
    job:start()
  end
end

--- Format the stats table into a markdown string.
---@param stats table
---@param date_str string
---@return string[]
M.format_report = function(stats, date_str)
  local lines = {}
  lines[#lines + 1] = "### 📊 Work Summary (" .. date_str .. ")"
  
  if stats.total_minutes == 0 then
    lines[#lines + 1] = "_No time logs found for this date._"
  else
    lines[#lines + 1] = string.format("- **Total Time Focused**: %s", tasks.format_duration(stats.total_minutes))
    lines[#lines + 1] = "- **Details**:"
    
    -- Sort tasks by time spent (descending)
    local sorted_tasks = {}
    for name, data in pairs(stats.tasks) do
      table.insert(sorted_tasks, { name = name, minutes = data.minutes, state = data.state })
    end
    table.sort(sorted_tasks, function(a, b) return a.minutes > b.minutes end)

    for _, t in ipairs(sorted_tasks) do
      lines[#lines + 1] = string.format("  - [%s] %s (%s)", t.state, t.name, tasks.format_duration(t.minutes))
    end
  end

  -- Add end marker for robust replacement
  lines[#lines + 1] = "<!-- obsidian-task-stats-end -->"

  return lines
end

return M
