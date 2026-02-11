local log = require "obsidian.log"
local srs = require "obsidian.srs"

---@param client obsidian.Client
return function(client, _)
  local stats = srs.get_stats_summary()
  local upcoming = {}

  srs.find_cards_async(tostring(client.dir), function(cards)
    vim.schedule(function()
      local total_cards = #cards
      local due_cards = vim.tbl_filter(function(c)
        return srs.is_due(c.due_date)
      end, cards)

      upcoming = srs.get_upcoming_reviews(cards, 7)

      local lines = {
        "",
        "  📊 SPACED REPETITION STATISTICS",
        "",
        "  " .. string.rep("═", 50),
        "",
        string.format("  Total Cards:       %d", total_cards),
        string.format("  Cards Due Today:   %d", #due_cards),
        "",
        "  " .. string.rep("─", 50),
        "",
        "  📈 REVIEW ACTIVITY",
        "",
        string.format("  Total Reviews:     %d", stats.total_reviews),
        string.format("  Reviews Today:     %d", stats.today_reviews),
        string.format("  New Cards Today:   %d", stats.today_new_cards),
        string.format("  🔥 Streak:          %d days", stats.streak),
        "",
        "  " .. string.rep("─", 50),
        "",
        "  📅 UPCOMING REVIEWS (Next 7 Days)",
        "",
      }

      for i = 0, 6 do
        local date = os.date("%Y-%m-%d (%a)", os.time() + (i * 86400))
        local iso_date = os.date("%Y-%m-%d", os.time() + (i * 86400))
        local count = upcoming[iso_date] or 0
        local marker = i == 0 and ">>>" or "   "
        table.insert(lines, string.format("  %s %s: %d cards", marker, date, count))
      end

      table.insert(lines, "")
      table.insert(lines, "  " .. string.rep("═", 50))
      table.insert(lines, "")
      table.insert(lines, "  Press 'q' to close")
      table.insert(lines, "")

      local buf = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

      local width = 60
      local height = #lines
      local row = math.floor((vim.o.lines - height) / 2)
      local col = math.floor((vim.o.columns - width) / 2)

      local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
        style = "minimal",
        border = "rounded",
        title = " SRS Statistics ",
        title_pos = "center",
      })

      vim.api.nvim_buf_set_option(buf, "modifiable", false)
      vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")

      vim.keymap.set("n", "q", function()
        vim.api.nvim_win_close(win, true)
      end, { buffer = buf })
    end)
  end)
end
