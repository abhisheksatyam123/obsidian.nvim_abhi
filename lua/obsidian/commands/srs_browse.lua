local log = require "obsidian.log"
local util = require "obsidian.util"
local srs = require "obsidian.srs"

---@param client obsidian.Client
return function(client, data)
  local args = data.args or ""
  local tag_filter = nil

  if args and args ~= "" then
    tag_filter = vim.split(args, " ", { plain = true })
  end

  srs.find_cards_async(tostring(client.dir), function(cards)
    vim.schedule(function()
      if tag_filter and #tag_filter > 0 then
        cards = srs.filter_by_tags(cards, tag_filter)
      end

      if #cards == 0 then
        log.info(tag_filter and "No cards found with specified tags!" or "No cards found in vault!")
        return
      end

      local entries = {}
      for _, card in ipairs(cards) do
        local status = card.is_new and "NEW" or (srs.is_due(card.due_date) and "DUE" or srs.days_until_due(card.due_date) .. "d")
        local type_icon = card.is_cloze and "📝" or (card.is_reversed and "🔄" or "📄")

        local display = string.format("[%s] %s %s :: %s", status, type_icon, card.question:sub(1, 30), card.answer:sub(1, 30))

        entries[#entries + 1] = {
          value = card,
          display = display,
          ordinal = card.question,
          filename = card.file_path,
          lnum = card.line_num,
        }
      end

      local pickers = require "telescope.pickers"
      local finders = require "telescope.finders"
      local conf = require("telescope.config").values
      local actions = require "telescope.actions"
      local action_state = require "telescope.actions.state"

      pickers.new({}, {
        prompt_title = string.format("Card Browser (%d cards)", #cards),
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
  end)
end
