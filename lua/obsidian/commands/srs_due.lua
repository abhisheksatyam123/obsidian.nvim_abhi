local log = require "obsidian.log"
local util = require "obsidian.util"
local srs = require "obsidian.srs"

---@param client obsidian.Client
return function(client, _)

  srs.find_cards_async(tostring(client.dir), function(cards)
    local due_cards = vim.tbl_filter(function(card)
      return srs.is_due(card.due_date)
    end, cards)

    if #due_cards == 0 then
      log.info "No cards due for review!"
      return
    end

    ---@type obsidian.PickerEntry[]
    local entries = {}
    for _, card in ipairs(due_cards) do
      local status = card.is_new and "NEW" or string.format("due: %s", card.due_date)
      local display = string.format("[%s] %s :: %s", status, card.question, card.answer)

      entries[#entries + 1] = {
        value = card,
        display = display,
        ordinal = card.question,
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
        prompt_title = string.format("SRS Due Cards (%d)", #due_cards),
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
  end, { due_only = true })
end
