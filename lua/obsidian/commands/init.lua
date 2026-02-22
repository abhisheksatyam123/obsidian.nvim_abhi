local util = require "obsidian.util"
local iter = require("obsidian.itertools").iter

local command_lookups = {
  ObsidianNew = "obsidian.commands.new",
  ObsidianOpen = "obsidian.commands.open",
  ObsidianTemplate = "obsidian.commands.template",
  ObsidianNewFromTemplate = "obsidian.commands.new_from_template",
  ObsidianWorkspace = "obsidian.commands.workspace",
  ObsidianPasteImg = "obsidian.commands.paste_img",
  ObsidianDebug = "obsidian.commands.debug",
  ObsidianSRSReview = "obsidian.commands.srs_review",
  ObsidianSRSDue = "obsidian.commands.srs_due",
  ObsidianSRSStats = "obsidian.commands.srs_stats",
  ObsidianSRSBrowse = "obsidian.commands.srs_browse",
  ObsidianTaskToggle = "obsidian.commands.task_toggle",
  ObsidianTaskPauseAll = "obsidian.commands.task_pause_all",
  ObsidianTaskDashboard = "obsidian.commands.task_dashboard",
  ObsidianTaskPriority = "obsidian.commands.task_priority",
  ObsidianTaskStats = "obsidian.commands.task_stats",
}

local M = setmetatable({
  commands = {},
}, {
  __index = function(t, k)
    local require_path = command_lookups[k]
    if not require_path then
      return
    end

    local mod = require(require_path)
    t[k] = mod

    return mod
  end,
})

---@class obsidian.CommandConfig
---@field opts table
---@field complete function|?
---@field func function|? (obsidian.Client, table) -> nil

---Register a new command.
---@param name string
---@param config obsidian.CommandConfig
M.register = function(name, config)
  if not config.func then
    config.func = function(client, data)
      return M[name](client, data)
    end
  end
  M.commands[name] = config
end

---Install all commands.
---
---@param client obsidian.Client
M.install = function(client)
  for command_name, command_config in pairs(M.commands) do
    local func = function(data)
      command_config.func(client, data)
    end

    if command_config.complete ~= nil then
      command_config.opts.complete = function(arg_lead, cmd_line, cursor_pos)
        return command_config.complete(client, arg_lead, cmd_line, cursor_pos)
      end
    end

    vim.api.nvim_create_user_command(command_name, func, command_config.opts)
  end
end

M.register("ObsidianNew", { opts = { nargs = "?", complete = "file", desc = "Create a new note" } })
M.register("ObsidianOpen", { opts = { nargs = "?", complete = "file", desc = "Open in Obsidian" } })
M.register("ObsidianTemplate", { opts = { nargs = "?", desc = "Insert a template" } })
M.register("ObsidianNewFromTemplate", { opts = { nargs = "?", desc = "Create a new note from a template" } })
M.register("ObsidianWorkspace", { opts = { nargs = "?", desc = "Change workspace" } })
M.register("ObsidianPasteImg", { opts = { nargs = "?", desc = "Paste an image" } })
M.register("ObsidianDebug", { opts = { nargs = 0, desc = "Log some information for debugging" } })
M.register("ObsidianSRSReview", { opts = { nargs = "?", desc = "Review due flashcards (optionally filter by tag)" } })
M.register("ObsidianSRSDue", { opts = { nargs = "?", desc = "List all due flashcards in a picker (optionally filter by tag)" } })
M.register("ObsidianSRSStats", { opts = { nargs = "?", desc = "Show spaced repetition statistics (optionally filter by tag)" } })
M.register("ObsidianSRSBrowse", { opts = { nargs = "?", desc = "Browse all flashcards (optionally filter by tags)" } })
M.register("ObsidianTaskToggle", { opts = { nargs = "?", desc = "Smart-toggle task state with time tracking" } })
M.register("ObsidianTaskPauseAll", { opts = { nargs = 0, desc = "Pause all active tasks across the vault" } })
M.register("ObsidianTaskDashboard", { opts = { nargs = 0, desc = "Open task dashboard aggregating all vault tasks" } })
M.register("ObsidianTaskPriority", { opts = { nargs = "?", desc = "Set or cycle task priority (#p1, #p2, #p3, #deferred)" } })
M.register("ObsidianTaskStats", { opts = { nargs = "?", desc = "Insert task statistics for a given date (defaults to today)" } })

return M
