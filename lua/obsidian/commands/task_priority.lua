local tasks = require "obsidian.tasks"
local log = require "obsidian.log"

---@param client obsidian.Client
---@param data table
return function(client, data)
  if not client.opts.tasks or not client.opts.tasks.enabled then
    log.warn "Task management is disabled. Set tasks.enabled = true in your config."
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1

  local args = data and data.args or ""

  if args == "1" then
    tasks.set_priority(bufnr, lnum, 1)
  elseif args == "2" then
    tasks.set_priority(bufnr, lnum, 2)
  elseif args == "3" then
    tasks.set_priority(bufnr, lnum, 3)
  elseif args == "none" then
    tasks.set_priority(bufnr, lnum, nil)
  elseif args == "defer" then
    tasks.defer_task(bufnr, lnum)
  else
    -- Cycle priority: None -> P1 -> P2 -> P3 -> None
    local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]
    local task = tasks.parse_task_line(line, lnum)
    if task then
      local next_p = nil
      if not task.priority then
        next_p = 1
      elseif task.priority == 1 then
        next_p = 2
      elseif task.priority == 2 then
        next_p = 3
      elseif task.priority == 3 then
        next_p = nil
      end
      tasks.set_priority(bufnr, lnum, next_p)
    end
  end
end
