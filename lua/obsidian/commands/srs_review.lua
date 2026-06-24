local log = require "obsidian.log"
local srs = require "obsidian.srs"
local Path = require "obsidian.path"
local util = require "obsidian.util"

local function make_box(title, text, width)
  local box_lines = {}
  local content_width = width - 4
  
  local title_len = #title
  local left_dashes = math.floor((content_width - title_len - 2) / 2)
  local right_dashes = content_width - title_len - 2 - left_dashes
  table.insert(box_lines, "  ╭" .. string.rep("─", left_dashes) .. " " .. title .. " " .. string.rep("─", right_dashes) .. "╮")
  
  for _, line in ipairs(vim.split(text, "\n")) do
    line = line:gsub("%s*$", "")
    if #line <= content_width then
      table.insert(box_lines, "  │ " .. line .. string.rep(" ", content_width - #line) .. " │")
    else
      local pos = 1
      while pos <= #line do
        local chunk = string.sub(line, pos, pos + content_width - 1)
        table.insert(box_lines, "  │ " .. chunk .. string.rep(" ", content_width - #chunk) .. " │")
        pos = pos + content_width
      end
    end
  end
  
  table.insert(box_lines, "  ╰" .. string.rep("─", content_width) .. "╯")
  return box_lines
end

local function apply_review_highlights(buf)
  vim.api.nvim_buf_call(buf, function()
    vim.cmd([[
      syntax match SRSKeyAgain "🔴 \[1\] Again"
      highlight link SRSKeyAgain DiagnosticError
      syntax match SRSKeyHard "🟡 \[2\] Hard"
      highlight link SRSKeyHard DiagnosticWarn
      syntax match SRSKeyGood "🟢 \[3\] Good"
      highlight link SRSKeyGood DiagnosticOk
      syntax match SRSKeyEasy "🔵 \[4\] Easy"
      highlight link SRSKeyEasy DiagnosticInfo
      
      syntax match SRSActionEdit "\[e\] Edit"
      highlight link SRSActionEdit Special
      syntax match SRSActionQuit "\[q\] Quit"
      highlight link SRSActionQuit Comment
      
      syntax match SRSProgressHeader "Card \d\+ / \d\+"
      highlight link SRSProgressHeader Type
      
      syntax match SRSBorderBox "[╭─╮│╰╯]"
      highlight link SRSBorderBox FloatBorder
    ]])
  end)
end

return function(client, data)
  local all_cards = {}
  local filter_tag = data.args and data.args ~= "" and data.args or client.opts.srs.tag

  local function start_review(tag)
    srs.find_cards_async(tostring(client.dir), function(cards)
      vim.schedule(function()
        srs.find_system_blocks_async(tostring(client.dir), function(blocks)
          vim.schedule(function()
            for _, b in ipairs(blocks) do table.insert(cards, b) end

            local due_cards = vim.tbl_filter(function(card)
              return srs.is_due(card.due_date)
            end, cards)

            local config = client.opts.srs or {}
            due_cards = srs.apply_review_limits(due_cards, config)

            if #due_cards == 0 then
              log.info(tag and string.format("No cards due for review with tag #%s!", tag) or "No cards due for review!")
              return
            end

            local card_idx = 1
            local reveal_state = { step = 1, finished = false }
            local review_buf, review_win = nil, nil
            local new_cards_reviewed = 0

            local function close_review()
              if review_win and vim.api.nvim_win_is_valid(review_win) then vim.api.nvim_win_close(review_win, true) end
              if review_buf and vim.api.nvim_buf_is_valid(review_buf) then vim.api.nvim_buf_delete(review_buf, { force = true }) end
            end

            local function render_card()
              if not review_buf or not vim.api.nvim_buf_is_valid(review_buf) then return end
              local card = due_cards[card_idx]
              local lines = {}
              
              -- Header: Location & Progress
              local filename = Path.new(card.file_path).name
              local location = filename
              if card.section then
                location = string.format("%s > %s", filename, card.section)
              end
              local tag_header = tag and string.format(" [#%s]", tag:gsub("^#", "")) or ""
              table.insert(lines, string.format("  📂 %s%s  |  Card %d / %d", location, tag_header, card_idx, #due_cards))
              table.insert(lines, "  " .. string.rep("━", 58))
              table.insert(lines, "")

              local box_width = 58

              if card.layout_type == "classic" then
                -- CLASSIC LAYOUT (Clean, simple Question/Answer)
                local question_text = ""
                local answer_text = ""

                if card.is_block then
                  -- It's a single-line block (like a single cloze or highlight)
                  local line = card.block_lines[1]
                  local marker = card.block_markers[1]
                  local pattern = util.escape_magic_characters(marker.raw)
                  if reveal_state.finished then
                    question_text = line:gsub(pattern, marker.text)
                    answer_text = marker.text
                  else
                    question_text = line:gsub(pattern, "[...]")
                  end
                else
                  -- It's a standard Question::Answer or ? card
                  if card.is_reversed then
                    question_text = card.answer
                    answer_text = card.question
                  else
                    question_text = card.question
                    answer_text = card.answer
                  end
                end

                for _, l in ipairs(make_box("Question", question_text, box_width)) do
                  table.insert(lines, l)
                end
                table.insert(lines, "")

                if reveal_state.finished then
                  for _, l in ipairs(make_box("Answer", answer_text, box_width)) do
                    table.insert(lines, l)
                  end
                else
                  table.insert(lines, "  Press <Space> or <CR> to reveal answer")
                end

              else
                -- SYSTEM LAYOUT (Progressive reveal for sequences)
                local total_markers = #card.block_markers
                local current_m = card.block_markers[reveal_state.step]
                
                local system_lines = {}
                for i, line in ipairs(card.block_lines) do
                  if i > current_m.line_idx and not reveal_state.finished then
                    break -- Hide future lines
                  end
                  
                  local display_line = line
                  local markers = srs.extract_markers(line)
                  
                  -- Process markers from right to left to avoid offset issues with string replacement
                  table.sort(markers, function(a, b) return #a.raw > #b.raw end)

                  for _, m in ipairs(markers) do
                    local found = false
                    for j = 1, reveal_state.step do
                      if card.block_markers[j].raw == m.raw and card.block_markers[j].line_idx == i then
                        found = true
                        if j == reveal_state.step and not reveal_state.finished then
                          local label_map = { p="PURPOSE", s="STRUCTURE", f="FLOW", r="LINK", e="EXIT", l="LOOP", v="LEVERAGE", c="FACT" }
                          local label = string.format("[%s%d: %s]", m.type:upper(), m.num, label_map[m.type] or "STEP")
                          display_line = display_line:gsub(util.escape_magic_characters(m.raw), label)
                        else
                          display_line = display_line:gsub(util.escape_magic_characters(m.raw), m.text)
                        end
                        break
                      end
                    end
                    
                    if not found and not reveal_state.finished then
                      display_line = display_line:gsub(util.escape_magic_characters(m.raw), "[...]")
                    elseif not found and reveal_state.finished then
                      display_line = display_line:gsub(util.escape_magic_characters(m.raw), m.text)
                    end
                  end
                  table.insert(system_lines, display_line)
                end

                for _, l in ipairs(make_box("Sequence Review", table.concat(system_lines, "\n"), box_width)) do
                  table.insert(lines, l)
                end
                
                if not reveal_state.finished then
                  table.insert(lines, "")
                  table.insert(lines, string.format("  *Step %d / %d* | Press <Space> to advance", reveal_state.step, total_markers))
                end
              end

              if reveal_state.finished then
                table.insert(lines, "")
                table.insert(lines, "  ╭────────────────────────── Rate Card ──────────────────────────╮")
                table.insert(lines, "  │  🔴 [1] Again    🟡 [2] Hard    🟢 [3] Good    🔵 [4] Easy  │")
                table.insert(lines, "  ╰───────────────────────────────────────────────────────────────╯")
                table.insert(lines, string.format("  *(Interval: %dd, Ease: %.2f)*", card.interval, card.ease / 100))
              end

              table.insert(lines, "")
              table.insert(lines, "  [e] Edit  [q] Quit")

              vim.api.nvim_buf_set_option(review_buf, "modifiable", true)
              vim.api.nvim_buf_set_lines(review_buf, 0, -1, false, lines)
              vim.api.nvim_buf_set_option(review_buf, "modifiable", false)
            end

            local function advance()
              local card = due_cards[card_idx]
              if card.is_block and not reveal_state.finished then
                if reveal_state.step < #card.block_markers then
                  reveal_state.step = reveal_state.step + 1
                else
                  reveal_state.finished = true
                end
              else
                reveal_state.finished = true
              end
              render_card()
            end

            local function grade(button)
              if not reveal_state.finished then return end
              local card = due_cards[card_idx]
              srs.review_card(card, button)
              if card.is_new then new_cards_reviewed = new_cards_reviewed + 1 end
              card_idx = card_idx + 1
              if card_idx > #due_cards then
                srs.update_stats(#due_cards, new_cards_reviewed)
                close_review()
                log.info("Review complete! Reviewed %d cards.", #due_cards)
              else
                reveal_state = { step = 1, finished = false }
                render_card()
              end
            end

            review_buf = vim.api.nvim_create_buf(false, true)
            vim.api.nvim_buf_set_option(review_buf, "filetype", "markdown")
            local width = 64
            local height = math.min(26, vim.o.lines - 4)
            review_win = vim.api.nvim_open_win(review_buf, true, {
              relative = "editor", width = width, height = height,
              row = math.floor((vim.o.lines - height) / 2),
              col = math.floor((vim.o.columns - width) / 2),
              style = "minimal", border = "rounded", title = " Obsidian Systems Review ", title_pos = "center"
            })
            vim.api.nvim_win_set_option(review_win, "wrap", true)
            
            local map = function(k, f) vim.keymap.set("n", k, f, { buffer = review_buf, silent = true }) end
            map("<Space>", advance)
            map("<CR>", advance)
            map("1", function() grade("again") end)
            map("2", function() grade("hard") end)
            map("3", function() grade("good") end)
            map("4", function() grade("easy") end)
            map("q", close_review)
            map("<Esc>", close_review)
            map("e", function()
              local card = due_cards[card_idx]
              close_review()
              util.open_buffer(card.file_path, { line = card.line_num })
            end)

            apply_review_highlights(review_buf)
            render_card()
          end)
        end, { tag = tag })
      end)
    end, { tag = tag, due_only = true })
  end

  if filter_tag then
    start_review(filter_tag)
  else
    -- Open tag picker
    log.info "Scanning vault for tags..."
    srs.get_vault_tags_async(tostring(client.dir), function(tags)
      if #tags == 0 then
        log.info "No tags found in note frontmatters. Starting full review..."
        start_review(nil)
        return
      end

      log.info(string.format("Found %d tags. Opening picker...", #tags))
      vim.schedule(function()
        local pickers = require "telescope.pickers"
        local finders = require "telescope.finders"
        local conf = require("telescope.config").values
        local actions = require "telescope.actions"
        local action_state = require "telescope.actions.state"

        pickers.new({}, {
          prompt_title = "Select Tag for SRS Review",
          finder = finders.new_table {
            results = tags,
          },
          sorter = conf.generic_sorter {},
          attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
              actions.close(prompt_bufnr)
              local selection = action_state.get_selected_entry()
              if selection then
                start_review(selection[1])
              end
            end)
            return true
          end,
        }):find()
      end)
    end)
  end
end
