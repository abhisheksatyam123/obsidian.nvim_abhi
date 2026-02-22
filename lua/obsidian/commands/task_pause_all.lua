local tasks = require "obsidian.tasks"
local log = require "obsidian.log"

---@param client obsidian.Client
return function(client)
  if not client.opts.tasks.enabled then
    log.warn "Task management is disabled. Set tasks.enabled = true in your config."
    return
  end

  local vault_root = tostring(client.current_workspace.root)
  tasks.pause_all_active(vault_root)
end
