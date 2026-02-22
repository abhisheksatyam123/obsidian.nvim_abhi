local log = require "obsidian.log"
local srs = require "obsidian.srs"

---@param client obsidian.Client
return function(client, data)
  local stats = srs.get_stats_summary()
  local upcoming = {}
  local filter_tag = data.args and data.args ~= "" and data.args or client.opts.srs.tag

  local function show_stats(tag)
    srs.find_cards_async(tostring(client.dir), function(cards)
      vim.schedule(function()
        srs.find_system_blocks_async(tostring(client.dir), function(blocks)
          vim.schedule(function()
            for _, b in ipairs(blocks) do table.insert(cards, b) end

            local total_cards = #cards
            local due_cards = vim.tbl_filter(function(c)
              return srs.is_due(c.due_date)
            end, cards)

            upcoming = srs.get_upcoming_reviews(cards, 7)

            local function make_bar(current, total, width)
              if total == 0 then return string.rep("░", width) end
              local ratio = math.min(1, current / total)
              local filled = math.floor(ratio * width)
              return string.rep("█", filled) .. string.rep("░", width - filled)
            end

            local title = tag and string.format("  # 📊 SRS Summary [#%s]", tag) or "  # 📊 Spaced Repetition Summary"

            local lines = {
              "",
              title,
              "",
              "  " .. string.rep("━", 54),
              "",
              string.format("  **Total Cards:**     %d", total_cards),
              string.format("  **Cards Due Today:** %d", #due_cards),
              "  " .. make_bar(#due_cards, total_cards, 40),
              "",
              "  " .. string.rep("─", 54),
              "",
              "  ### 📈 Review Activity",
              "",
              string.format("  - Total Reviews:     %d", stats.total_reviews),
              string.format("  - Reviews Today:     %d", stats.today_reviews),
              string.format("  - New Cards Today:   %d", stats.today_new_cards),
              string.format("  - 🔥 Streak:          **%d days**", stats.streak),
              "",
              "  " .. string.rep("─", 54),
              "",
              "  ### 📅 Upcoming Reviews (7 Day Forecast)",
              "",
            }

            for i = 0, 6 do
              local date_display = os.date("%a, %b %d", os.time() + (i * 86400))
              local iso_date = os.date("%Y-%m-%d", os.time() + (i * 86400))
              local count = upcoming[iso_date] or 0
              local bar = make_bar(count, math.max(20, total_cards / 5), 15)
              local marker = i == 0 and "→" or " "
              table.insert(lines, string.format("  %s %-12s | %s (%d)", marker, date_display, bar, count))
            end

            table.insert(lines, "")
            table.insert(lines, "  " .. string.rep("━", 54))
            table.insert(lines, "")
            table.insert(lines, "  *Press 'q' to close this dashboard*")
            table.insert(lines, "")

            local buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
            vim.api.nvim_buf_set_option(buf, "filetype", "markdown")

            local width = 64
            local height = math.min(#lines, vim.o.lines - 4)
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
              title = " SRS Insights ",
              title_pos = "center",
            })

            vim.api.nvim_buf_set_option(buf, "modifiable", false)
            vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
            vim.api.nvim_win_set_option(win, "conceallevel", 2)

            vim.keymap.set("n", "q", function()
              vim.api.nvim_win_close(win, true)
            end, { buffer = buf })
            
            vim.keymap.set("n", "<Esc>", function()
              vim.api.nvim_win_close(win, true)
            end, { buffer = buf })
          end)
        end, { tag = tag, due_only = false })
      end)
    end, { tag = tag, due_only = false })
  end

  if filter_tag then
    show_stats(filter_tag)
  else
    log.info "Scanning vault for tags..."
    srs.get_vault_tags_async(tostring(client.dir), function(tags)
      if #tags == 0 then
        show_stats(nil)
        return
      end
      vim.schedule(function()
        local pickers = require "telescope.pickers"
        local finders = require "telescope.finders"
        local conf = require("telescope.config").values
        local actions = require "telescope.actions"
        local action_state = require "telescope.actions.state"
        pickers.new({}, {
          prompt_title = "Select Tag for SRS Stats",
          finder = finders.new_table { results = tags },
          sorter = conf.generic_sorter {},
          attach_mappings = function(prompt_bufnr)
            actions.select_default:replace(function()
              actions.close(prompt_bufnr)
              local selection = action_state.get_selected_entry()
              if selection then
                show_stats(selection[1])
              end
            end)
            return true
          end,
        }):find()
      end)
    end)
  end
end
