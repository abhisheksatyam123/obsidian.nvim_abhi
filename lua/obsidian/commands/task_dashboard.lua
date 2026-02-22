local tasks = require "obsidian.tasks"
local log = require "obsidian.log"
local util = require "obsidian.util"

---@param client obsidian.Client
---@param data table
return function(client, data)
  if not client.opts.tasks or not client.opts.tasks.enabled then
    log.warn "Task management is disabled. Set tasks.enabled = true in your config."
    return
  end

  local vault_root = tostring(client.current_workspace.root)
  local stale_days = client.opts.tasks.stale_threshold_days or 3

  tasks.aggregate_tasks(vault_root, { stale_threshold_days = stale_days }, function(all_tasks)
    local lines = {}
    local locations = {} -- maps line index -> {file, lnum} for jump support

    local function add_section(title, items, formatter)
      if #items == 0 then
        return
      end
      lines[#lines + 1] = ""
      lines[#lines + 1] = "## " .. title .. " (" .. #items .. ")"
      lines[#lines + 1] = ""
      for _, item in ipairs(items) do
        local display = formatter(item)
        lines[#lines + 1] = display
        if item.file and item.lnum then
          locations[#lines] = { file = item.file, lnum = item.lnum }
        end
      end
    end

    lines[#lines + 1] = "# Task Dashboard (Focus Mode)"
    lines[#lines + 1] = ""
    lines[#lines + 1] = string.format(
      "P1: %d | Active: %d | P2: %d | P3: %d | Done: %d",
      #all_tasks.p1,
      #all_tasks.active,
      #all_tasks.p2,
      #all_tasks.p3,
      #all_tasks.done
    )

    -- 1. High Priority Focus
    add_section("🔥 CURRENT FOCUS (P1)", all_tasks.p1, function(t)
      local text = string.match(t.line, "^%s*%- %[.%]%s*(.*)") or t.line
      return "- [" .. t.state .. "] " .. text .. "  `" .. t.display_file .. ":" .. t.lnum .. "`"
    end)

    -- 2. Currently Active
    add_section("🟢 ACTIVE (timer running)", all_tasks.active, function(t)
      local text = string.match(t.line, "^%s*%- %[.%]%s*(.*)") or t.line
      return "- [/] " .. text .. "  `" .. t.display_file .. ":" .. t.lnum .. "`"
    end)

    -- 3. Next Up (P2)
    add_section("📅 NEXT UP (P2)", all_tasks.p2, function(t)
      local text = string.match(t.line, "^%s*%- %[.%]%s*(.*)") or t.line
      return "- [" .. t.state .. "] " .. text .. "  `" .. t.display_file .. ":" .. t.lnum .. "`"
    end)

    -- 4. Starving Projects
    add_section("⚠️ STARVING PROJECTS (>" .. stale_days .. " days untouched)", all_tasks.starving, function(t)
      return "- " .. t.display_file .. " (last modified: " .. t.last_modified .. ", " .. t.days_stale .. "d ago)"
    end)

    -- 5. Backlog (P3 and others)
    add_section("📥 BACKLOG (P3 / Other)", all_tasks.todo, function(t)
      -- Filter out tasks already shown in P1/P2/P3 if they were todos
      if t.priority and t.priority < 3 then return end -- already in P1 or P2
      local text = string.match(t.line, "^%s*%- %[.%]%s*(.*)") or t.line
      return "- [ ] " .. text .. "  `" .. t.display_file .. ":" .. t.lnum .. "`"
    end)

    -- 6. Deferred
    add_section("💤 DEFERRED (Not important right now)", all_tasks.deferred, function(t)
      local text = string.match(t.line, "^%s*%- %[.%]%s*(.*)") or t.line
      return "- [-] " .. text .. "  `" .. t.display_file .. ":" .. t.lnum .. "`"
    end)

    -- Open a scratch buffer with the dashboard.
    vim.cmd "enew"
    local bufnr = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.bo[bufnr].buftype = "nofile"
    vim.bo[bufnr].bufhidden = "wipe"
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].modifiable = false
    vim.bo[bufnr].filetype = "markdown"
    vim.api.nvim_buf_set_name(bufnr, "obsidian://task-dashboard")

    -- Set up <CR> to jump to the task's source file.
    vim.keymap.set("n", "<CR>", function()
      local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
      local loc = locations[cursor_line]
      if loc then
        -- Close the dashboard buffer first.
        vim.cmd "bwipeout"
        util.open_buffer(loc.file, { line = loc.lnum })
      end
    end, { buffer = bufnr, desc = "Jump to task source" })

    -- Set up q to close.
    vim.keymap.set("n", "q", function()
      vim.cmd "bwipeout"
    end, { buffer = bufnr, desc = "Close dashboard" })

    log.info "Task dashboard loaded. Press <CR> to jump, q to close."
  end)
end
