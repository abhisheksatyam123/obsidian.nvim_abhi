local abc = require "obsidian.abc"

local M = {}

---Like Python's `defaultdict`.
---@class DefaultTbl : obsidian.ABC
---@field __factory function
local DefaultTbl = abc.new_class {
  __tostring = function(self)
    local inner = self.__factory()
    if getmetatable(inner) == getmetatable(self) then
      return string.format("DefaultTbl(%s)", inner)
    else
      return string.format("DefaultTbl(%s)", vim.inspect(inner))
    end
  end,
}

DefaultTbl.mt.__index = function(self, k)
  if DefaultTbl[k] then
    self[k] = DefaultTbl[k]
  else
    self[k] = self.__factory()
  end
  return self[k]
end

M.DefaultTbl = DefaultTbl

---@param factory function
---@return DefaultTbl
DefaultTbl.new = function(factory)
  local self = DefaultTbl.init {
    __factory = factory,
  }
  return self
end

---Create a DefaultTbl with a factory function that returns an empty table.
---In Python, this would be equivalent to `DefaultDict(dict)`.
---@return DefaultTbl
DefaultTbl.with_tbl = function()
  return DefaultTbl.new(function()
    return {}
  end)
end

return M
