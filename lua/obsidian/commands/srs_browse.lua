local log = require "obsidian.log"
local util = require "obsidian.util"
local srs = require "obsidian.srs"
local Path = require "obsidian.path"

---@param client obsidian.Client
return function(client, data)
  local filter_tag = data.args and data.args ~= "" and data.args or client.opts.srs.tag

  local function show_browser(tag)
    srs.find_cards_async(tostring(client.dir), function(cards)
      srs.find_system_blocks_async(tostring(client.dir), function(blocks)
        for _, b in ipairs(blocks) do table.insert(cards, b) end

        if #cards == 0 then
          log.info(tag and string.format("No cards found with tag #%s!", tag) or "No cards found in vault!")
          return
        end

        local entries = {}
        for _, card in ipairs(cards) do
          local status = card.is_new and "NEW" or (srs.is_due(card.due_date) and "DUE" or srs.days_until_due(card.due_date) .. "d")
          local type_icon = card.is_block and "🧱" or (card.is_reversed and "🔄" or "📄")
          
          local q = card.question or (card.is_block and card.block_lines[1]:sub(1, 40) .. "...") or "Unknown"
          local a = card.answer or (card.is_block and #card.block_markers .. " steps") or "Unknown"

          local location = Path.new(card.file_path).name
          if card.section then
            location = location .. " > " .. card.section
          end

          local display = string.format("[%s] %s %s :: %s (%s)", status, type_icon, q, a, location)

          entries[#entries + 1] = {
            value = card,
            display = display,
            ordinal = q,
            filename = card.file_path,
            lnum = card.line_num,
          }
        end

        vim.schedule(function()
          local pickers = require "telescope.pickers"
          local finders = require "telescope.finders"
          local conf = require("telescope.config").values
          local actions = require "telescope.actions"
          local action_state = require "telescope.actions.state"

          pickers.new({}, {
            prompt_title = string.format("Card Browser%s (%d cards)", tag and " #" .. tag or "", #cards),
            finder = finders.new_table {
              results = entries,
              entry_maker = function(entry)
                return {
                  value = entry,
                  display = entry.display,
                  ordinal = entry.display,
                  filename = entry.filename,
                  lnum = entry.lnum,
                }
              end,
            },
            sorter = conf.generic_sorter {},
            attach_mappings = function(prompt_bufnr)
              actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = action_state.get_selected_entry()
                util.open_buffer(selection.value.filename, { line = selection.value.lnum })
              end)
              return true
            end,
          }):find()
        end)
      end, { tag = tag })
    end, { tag = tag })
  end

  if filter_tag then
    show_browser(filter_tag)
  else
    srs.get_vault_tags_async(tostring(client.dir), function(tags)
      if #tags == 0 then
        show_browser(nil)
        return
      end
      vim.schedule(function()
        local pickers = require "telescope.pickers"
        local finders = require "telescope.finders"
        local conf = require("telescope.config").values
        local actions = require "telescope.actions"
        local action_state = require "telescope.actions.state"
        pickers.new({}, {
          prompt_title = "Select Tag for SRS Browser",
          finder = finders.new_table { results = tags },
          sorter = conf.generic_sorter {},
          attach_mappings = function(prompt_bufnr)
            actions.select_default:replace(function()
              actions.close(prompt_bufnr)
              local selection = action_state.get_selected_entry()
              show_browser(selection[1])
            end)
            return true
          end,
        }):find()
      end)
    end)
  end
end
