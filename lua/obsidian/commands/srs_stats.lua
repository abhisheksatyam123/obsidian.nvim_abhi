local log = require "obsidian.log"
local srs = require "obsidian.srs"

local function make_box_lines(title, content_lines, width)
  local box_lines = {}
  local content_width = width - 4
  
  local title_len = #title
  local left_dashes = math.floor((content_width - title_len - 2) / 2)
  local right_dashes = content_width - title_len - 2 - left_dashes
  table.insert(box_lines, "  ╭" .. string.rep("─", left_dashes) .. " " .. title .. " " .. string.rep("─", right_dashes) .. "╮")
  
  for _, line in ipairs(content_lines) do
    if #line <= content_width then
      table.insert(box_lines, "  │ " .. line .. string.rep(" ", content_width - #line) .. " │")
    else
      local chunk = string.sub(line, 1, content_width)
      table.insert(box_lines, "  │ " .. chunk .. " │")
    end
  end
  
  table.insert(box_lines, "  ╰" .. string.rep("─", content_width) .. "╯")
  return box_lines
end

local function apply_stats_highlights(buf)
  vim.api.nvim_buf_call(buf, function()
    vim.cmd([[
      syntax match SRSStatsTitle "📊.*"
      highlight link SRSStatsTitle Title
      
      syntax match SRSStreak "🔥 Current Streak:.*"
      highlight link SRSStreak Special
      
      syntax match SRSBarFilled "█"
      highlight link SRSBarFilled DiagnosticOk
      
      syntax match SRSBarEmpty "░"
      highlight link SRSBarEmpty Comment
      
      syntax match SRSForecastToday "→.*"
      highlight link SRSForecastToday Function
      
      syntax match SRSBorderBox "[╭─╮│╰╯]"
      highlight link SRSBorderBox FloatBorder
    ]])
  end)
end

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

            local box_width = 58
            local title = tag and string.format("📊 SRS Summary [#%s]", tag) or "📊 Spaced Repetition Summary"

            -- 1. Vault Status Box
            local progress_bar = make_bar(#due_cards, total_cards, 20)
            local status_content = {
              string.format("Total Cards:     %d", total_cards),
              string.format("Cards Due Today: %d", #due_cards),
              string.format("Progress:        %s", progress_bar),
            }
            local status_box = make_box_lines("Vault Status", status_content, box_width)

            -- 2. Review Activity Box
            local activity_content = {
              string.format("📈 Total Reviews:   %d", stats.total_reviews),
              string.format("⚡ Reviews Today:    %d", stats.today_reviews),
              string.format("🆕 New Cards Today:  %d", stats.today_new_cards),
              string.format("🔥 Current Streak:  %d days", stats.streak),
            }
            local activity_box = make_box_lines("Review Activity", activity_content, box_width)

            -- 3. 7-Day Forecast Box
            local forecast_content = {}
            for i = 0, 6 do
              local date_display = os.date("%a, %b %d", os.time() + (i * 86400))
              local iso_date = os.date("%Y-%m-%d", os.time() + (i * 86400))
              local count = upcoming[iso_date] or 0
              local bar = make_bar(count, math.max(20, total_cards / 5), 10)
              local marker = i == 0 and "→" or " "
              table.insert(forecast_content, string.format("%s %-12s | %s (%d)", marker, date_display, bar, count))
            end
            local forecast_box = make_box_lines("7-Day Forecast", forecast_content, box_width)

            local lines = {
              "",
              "  " .. title,
              "",
            }
            for _, l in ipairs(status_box) do table.insert(lines, l) end
            table.insert(lines, "")
            for _, l in ipairs(activity_box) do table.insert(lines, l) end
            table.insert(lines, "")
            for _, l in ipairs(forecast_box) do table.insert(lines, l) end
            table.insert(lines, "")
            table.insert(lines, "  *Press 'q' or <Esc> to close this dashboard*")
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

            apply_stats_highlights(buf)

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
