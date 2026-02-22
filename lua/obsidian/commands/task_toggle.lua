local tasks = require "obsidian.tasks"
local log = require "obsidian.log"

---@param client obsidian.Client
---@param data table
return function(client, data)
  if not client.opts.tasks.enabled then
    log.warn "Task management is disabled. Set tasks.enabled = true in your config."
    return
  end

  local bufnr = vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1

  local args = data and data.args or ""

  if args == "done" then
    tasks.mark_done(bufnr, lnum)
  elseif args == "blocked" then
    tasks.mark_blocked(bufnr, lnum)
  elseif args == "cancel" then
    tasks.mark_cancelled(bufnr, lnum)
  else
    tasks.smart_toggle(bufnr, lnum)
  end
end
