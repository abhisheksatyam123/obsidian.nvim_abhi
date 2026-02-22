local stats_mod = require "obsidian.tasks_stats"
local log = require "obsidian.log"

---@param client obsidian.Client
---@param data table
return function(client, data)
  if not client.opts.tasks.enabled then
    log.warn "Task management is disabled."
    return
  end

  local date_str = (data.args and data.args ~= "") and data.args or os.date("%Y-%m-%d")
  local vault_root = tostring(client.dir)

  stats_mod.get_daily_stats(vault_root, date_str, function(stats)
    local report = stats_mod.format_report(stats, date_str)
    
    -- Insert at cursor
    local bufnr = vim.api.nvim_get_current_buf()
    local cursor = vim.api.nvim_win_get_cursor(0)
    local row = cursor[1]
    
    vim.api.nvim_buf_set_lines(bufnr, row, row, false, report)
    log.info("Inserted task statistics for %s", date_str)
  end)
end
