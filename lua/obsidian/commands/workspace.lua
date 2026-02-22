local log = require "obsidian.log"
local Workspace = require "obsidian.workspace"

---@param client obsidian.Client
return function(client, data)
  if not data.args or string.len(data.args) == 0 then

    local options = {}
    for i, spec in ipairs(client.opts.workspaces) do
      local workspace = Workspace.new_from_spec(spec)
      if workspace == client.current_workspace then
        options[#options + 1] = string.format("*[%d] %s @ '%s'", i, workspace.name, workspace.path)
      else
        options[#options + 1] = string.format("[%d] %s @ '%s'", i, workspace.name, workspace.path)
      end
    end

    vim.schedule(function()
      vim.ui.select(options, {
        prompt = "Workspaces",
      }, function(workspace_str)
        if workspace_str then
          local idx = tonumber(string.match(workspace_str, "%*?%[(%d+)]"))
          client:switch_workspace(client.opts.workspaces[idx].name, { lock = true })
        end
      end)
    end)
  else
    client:switch_workspace(data.args, { lock = true })
  end
end
