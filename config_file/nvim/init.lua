vim.g.mapleader = "\\"
vim.g.maplocalleader = "\\"

vim.opt.clipboard = "unnamedplus"
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true
vim.opt.swapfile = false
vim.opt.conceallevel = 2
vim.wo.number = true
vim.opt.timeoutlen = 1000


-- Compatibility patch for Neovim 0.11+ (ft_to_lang was removed)
-- Forced definition to ensure Telescope never sees a nil value
if vim.treesitter then
  vim.treesitter.ft_to_lang = function(ft)
    local ok, lang = pcall(function() return vim.treesitter.language.get_lang(ft) end)
    return (ok and lang) or ft
  end
end

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git",
    "clone",
    "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  spec = {
    { import = "plugins" },
  },
})

