local log = require "obsidian.log"
local srs = require "obsidian.srs"

return function(client, _)
  local all_cards = {}

  srs.find_cards_async(tostring(client.dir), function(cards)
    vim.schedule(function()
      all_cards = cards

      srs.find_cloze_cards_async(tostring(client.dir), function(cloze_cards)
        vim.schedule(function()
          for _, cloze in ipairs(cloze_cards) do
            table.insert(all_cards, cloze)
          end

          local due_cards = vim.tbl_filter(function(card)
            return srs.is_due(card.due_date)
          end, all_cards)

          local config = client.opts.srs or {}
          due_cards = srs.apply_review_limits(due_cards, config)

          if #due_cards == 0 then
            log.info "No cards due for review!"
            return
          end

          local card_idx = 1
          local answer_visible = false
          local review_buf = nil
          local review_win = nil
          local modified_files = {}
          local new_cards_reviewed = 0

          local function close_review()
            if review_win and vim.api.nvim_win_is_valid(review_win) then
              vim.api.nvim_win_close(review_win, true)
            end
            if review_buf and vim.api.nvim_buf_is_valid(review_buf) then
              vim.api.nvim_buf_delete(review_buf, { force = true })
            end
            review_win = nil
            review_buf = nil
          end

          local function render_card()
            if not review_buf or not vim.api.nvim_buf_is_valid(review_buf) then
              return
            end

            local card = due_cards[card_idx]
            local lines = {}
            local is_reversed = card.is_reversed
            local is_cloze = card.is_cloze

            local type_icon = is_cloze and "📝" or (is_reversed and "🔄" or "📄")

            lines[#lines + 1] = string.format("  Card %d / %d %s", card_idx, #due_cards, type_icon)
            lines[#lines + 1] = string.rep("─", 50)
            lines[#lines + 1] = ""

            if is_reversed then
              lines[#lines + 1] = "  A: " .. card.answer
              lines[#lines + 1] = ""
            else
              lines[#lines + 1] = "  Q: " .. card.question
              lines[#lines + 1] = ""
            end

            if answer_visible then
              lines[#lines + 1] = string.rep("─", 50)
              lines[#lines + 1] = ""
              if is_reversed then
                lines[#lines + 1] = "  Q: " .. card.question
              else
                lines[#lines + 1] = "  A: " .. card.answer
              end
              lines[#lines + 1] = ""
              lines[#lines + 1] = string.rep("─", 50)
              lines[#lines + 1] = ""
              lines[#lines + 1] = "  [1] Again  [2] Hard  [3] Good  [4] Easy"

              if card.is_new then
                lines[#lines + 1] = "  (New card)"
              else
                lines[#lines + 1] = string.format(
                  "  (interval: %dd, ease: %.2f)",
                  card.interval,
                  card.ease / 100
                )
              end
            else
              lines[#lines + 1] = string.rep("─", 50)
              lines[#lines + 1] = ""
              if is_reversed then
                lines[#lines + 1] = "  Press <Space> or <CR> to reveal question"
              else
                lines[#lines + 1] = "  Press <Space> or <CR> to reveal answer"
              end
            end

            lines[#lines + 1] = ""
            lines[#lines + 1] = "  [q] Quit"

            vim.api.nvim_buf_set_option(review_buf, "modifiable", true)
            vim.api.nvim_buf_set_lines(review_buf, 0, -1, false, lines)
            vim.api.nvim_buf_set_option(review_buf, "modifiable", false)
          end

          local function grade_and_advance(button)
            local card = due_cards[card_idx]
            local success = srs.review_card(card, button)

            if not success then
              close_review()
              return
            end

            if card.is_new then
              new_cards_reviewed = new_cards_reviewed + 1
            end

            modified_files[card.file_path] = true

            card_idx = card_idx + 1
            answer_visible = false

            if card_idx > #due_cards then
              srs.update_stats(#due_cards, new_cards_reviewed)
              close_review()
              log.info("Review complete! Reviewed %d card(s).", #due_cards)

              for file_path, _ in pairs(modified_files) do
                for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
                  if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_buf_get_name(bufnr) == file_path then
                    vim.api.nvim_buf_call(bufnr, function()
                      vim.cmd "edit!"
                    end)
                  end
                end
              end
              return
            end

            render_card()
          end

          local function show_answer()
            if not answer_visible then
              answer_visible = true
              render_card()
            end
          end

          review_buf = vim.api.nvim_create_buf(false, true)
          vim.api.nvim_buf_set_option(review_buf, "buftype", "nofile")
          vim.api.nvim_buf_set_option(review_buf, "bufhidden", "wipe")
          vim.api.nvim_buf_set_option(review_buf, "filetype", "obsidian-srs-review")

          local width = math.min(60, math.floor(vim.o.columns * 0.6))
          local height = math.min(20, math.floor(vim.o.lines * 0.5))
          local row = math.floor((vim.o.lines - height) / 2)
          local col = math.floor((vim.o.columns - width) / 2)

          review_win = vim.api.nvim_open_win(review_buf, true, {
            relative = "editor",
            width = width,
            height = height,
            row = row,
            col = col,
            style = "minimal",
            border = "rounded",
            title = " Obsidian SRS Review ",
            title_pos = "center",
          })

          vim.api.nvim_win_set_option(review_win, "wrap", true)
          vim.api.nvim_win_set_option(review_win, "cursorline", false)

          local buf_map = function(key, fn)
            vim.keymap.set("n", key, fn, { buffer = review_buf, nowait = true, silent = true })
          end

          buf_map("<Space>", show_answer)
          buf_map("<CR>", show_answer)

          buf_map("1", function()
            if answer_visible then grade_and_advance("again") end
          end)
          buf_map("2", function()
            if answer_visible then grade_and_advance("hard") end
          end)
          buf_map("3", function()
            if answer_visible then grade_and_advance("good") end
          end)
          buf_map("4", function()
            if answer_visible then grade_and_advance("easy") end
          end)

          buf_map("q", close_review)
          buf_map("<Esc>", close_review)

          render_card()
        end)
      end, { due_only = true })
    end)
  end, { due_only = true })
end
