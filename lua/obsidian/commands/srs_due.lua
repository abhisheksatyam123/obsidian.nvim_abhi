local log = require "obsidian.log"
local util = require "obsidian.util"
local srs = require "obsidian.srs"

---@param client obsidian.Client
return function(client, _)
  local picker = client:picker()
  if not picker then
    log.err "No picker configured"
    return
  end

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
      picker:pick(entries, {
        prompt_title = string.format("SRS Due Cards (%d)", #due_cards),
        callback = function(card)
          util.open_buffer(card.file_path, { line = card.line_num })
        end,
      })
    end)
  end, { due_only = true })
end
