-- ============================================================================
-- Lazy.nvim Configuration for obsidian.nvim
-- ============================================================================
-- Copy this file to your Neovim configuration: ~/.config/nvim/lua/plugins/obsidian.lua
-- or nvim/lua/plugins/obsidian.lua (depending on your setup)
--
-- This configuration includes:
-- - Basic vault/workspace setup
-- - SRS (Spaced Repetition System) for flashcard reviews
-- - Completion, pickers, and UI customization
-- - Daily notes and templates
-- ============================================================================

return {
  "epwalsh/obsidian.nvim",
  version = "*", -- Use latest release for stability
  lazy = true,
  ft = "markdown", -- Load only for markdown files

  -- Event-based loading (alternative to ft):
  -- event = {
  --   "BufReadPre " .. vim.fn.expand("~") .. "/Documents/Notes/*.md",
  --   "BufNewFile " .. vim.fn.expand("~") .. "/Documents/Notes/*.md",
  -- },

  dependencies = {
    -- Required
    "nvim-lua/plenary.nvim",

    -- Recommended: Completion
    "hrsh7th/nvim-cmp",

    -- Recommended: Picker (choose one)
    "nvim-telescope/telescope.nvim",
    -- Alternative: "ibhagwan/fzf-lua",
    -- Alternative: "echasnovski/mini.pick",

    -- Recommended: Syntax highlighting
    "nvim-treesitter/nvim-treesitter",
  },

  opts = {
    -- ============================================================================
    -- Workspaces (Vaults)
    -- ============================================================================
    workspaces = {
      {
        name = "personal",
        path = "~/Documents/Notes",
      },
      {
        name = "work",
        path = "~/Documents/Work",
        overrides = {
          notes_subdir = "notes",
        },
      },
    },

    -- ============================================================================
    -- SRS (Spaced Repetition System) - Flashcard Reviews
    -- ============================================================================
    srs = {
      enabled = true,                  -- Enable SRS commands
      max_new_per_day = 20,            -- Max new cards per day
      max_reviews_per_day = 100,       -- Max total reviews per day
      default_ease = 2.5,              -- Starting ease factor
      min_ease = 1.3,                  -- Minimum ease factor
      easy_bonus = 1.3,                -- Multiplier for "easy" responses
      hard_interval = 1.2,             -- Multiplier for "hard" responses
    },

    -- ============================================================================
    -- Notes Configuration
    -- ============================================================================
    notes_subdir = "notes",            -- Default folder for new notes
    new_notes_location = "notes_subdir", -- "current_dir" or "notes_subdir"

    -- Custom note ID function (Zettelkasten format)
    note_id_func = function(title)
      local suffix = ""
      if title ~= nil then
        suffix = title:gsub(" ", "-"):gsub("[^A-Za-z0-9-]", ""):lower()
      else
        for _ = 1, 4 do
          suffix = suffix .. string.char(math.random(65, 90))
        end
      end
      return tostring(os.time()) .. "-" .. suffix
    end,

    -- ============================================================================
    -- Daily Notes
    -- ============================================================================
    daily_notes = {
      folder = "notes/dailies",
      date_format = "%Y-%m-%d",
      alias_format = "%B %-d, %Y",
      default_tags = { "daily-notes" },
      template = nil, -- Set to "daily.md" to use a template
    },

    -- ============================================================================
    -- Completion
    -- ============================================================================
    completion = {
      nvim_cmp = true,
      min_chars = 2,
    },

    -- ============================================================================
    -- Key Mappings
    -- ============================================================================
    mappings = {
      -- Follow links with gf
      ["gf"] = {
        action = function()
          return require("obsidian").util.gf_passthrough()
        end,
        opts = { noremap = false, expr = true, buffer = true },
      },
      -- Toggle checkboxes
      ["<leader>ch"] = {
        action = function()
          return require("obsidian").util.toggle_checkbox()
        end,
        opts = { buffer = true },
      },
      -- Smart action (follow link or toggle checkbox)
      ["<cr>"] = {
        action = function()
          return require("obsidian").util.smart_action()
        end,
        opts = { buffer = true, expr = true },
      },
    },

    -- ============================================================================
    -- Wiki/Markdown Links
    -- ============================================================================
    preferred_link_style = "wiki", -- "wiki" or "markdown"

    wiki_link_func = function(opts)
      return require("obsidian.util").wiki_link_id_prefix(opts)
    end,

    markdown_link_func = function(opts)
      return require("obsidian.util").markdown_link(opts)
    end,

    -- ============================================================================
    -- Templates
    -- ============================================================================
    templates = {
      folder = "templates",
      date_format = "%Y-%m-%d",
      time_format = "%H:%M",
      substitutions = {},
    },

    -- ============================================================================
    -- Picker (Telescope, fzf-lua, or mini.pick)
    -- ============================================================================
    picker = {
      name = "telescope.nvim",
      note_mappings = {
        new = "<C-x>",      -- Create new note from query
        insert_link = "<C-l>", -- Insert link to selected note
      },
      tag_mappings = {
        tag_note = "<C-x>", -- Add tag(s) to current note
        insert_tag = "<C-l>", -- Insert tag at cursor
      },
    },

    -- ============================================================================
    -- Sorting
    -- ============================================================================
    sort_by = "modified",
    sort_reversed = true,
    search_max_lines = 1000,

    -- ============================================================================
    -- UI / Syntax Highlighting
    -- ============================================================================
    ui = {
      enable = true,
      update_debounce = 200,
      max_file_length = 5000,

      checkboxes = {
        [" "] = { char = "󰄱", hl_group = "ObsidianTodo" },
        ["x"] = { char = "", hl_group = "ObsidianDone" },
        [">"] = { char = "", hl_group = "ObsidianRightArrow" },
        ["~"] = { char = "󰰱", hl_group = "ObsidianTilde" },
        ["!"] = { char = "", hl_group = "ObsidianImportant" },
      },

      bullets = { char = "•", hl_group = "ObsidianBullet" },
      external_link_icon = { char = "", hl_group = "ObsidianExtLinkIcon" },
      reference_text = { hl_group = "ObsidianRefText" },
      highlight_text = { hl_group = "ObsidianHighlightText" },
      tags = { hl_group = "ObsidianTag" },
      block_ids = { hl_group = "ObsidianBlockID" },

      hl_groups = {
        ObsidianTodo = { bold = true, fg = "#f78c6c" },
        ObsidianDone = { bold = true, fg = "#89ddff" },
        ObsidianRightArrow = { bold = true, fg = "#f78c6c" },
        ObsidianTilde = { bold = true, fg = "#ff5370" },
        ObsidianImportant = { bold = true, fg = "#d73128" },
        ObsidianBullet = { bold = true, fg = "#89ddff" },
        ObsidianRefText = { underline = true, fg = "#c792ea" },
        ObsidianExtLinkIcon = { fg = "#c792ea" },
        ObsidianTag = { italic = true, fg = "#89ddff" },
        ObsidianBlockID = { italic = true, fg = "#89ddff" },
        ObsidianHighlightText = { bg = "#75662e" },
      },
    },

    -- ============================================================================
    -- Attachments (Images)
    -- ============================================================================
    attachments = {
      img_folder = "assets/imgs",

      img_name_func = function()
        return string.format("%s-", os.time())
      end,

      img_text_func = function(client, path)
        path = client:vault_relative_path(path) or path
        return string.format("![%s](%s)", path.name, path)
      end,
    },

    -- ============================================================================
    -- Callbacks
    -- ============================================================================
    callbacks = {
      post_setup = function(client) end,
      enter_note = function(client, note) end,
      leave_note = function(client, note) end,
      pre_write_note = function(client, note) end,
      post_set_workspace = function(client, workspace) end,
    },

    -- ============================================================================
    -- External URL/Image Handling
    -- ============================================================================
    follow_url_func = function(url)
      vim.fn.jobstart({ "open", url }) -- macOS
      -- vim.fn.jobstart({ "xdg-open", url }) -- Linux
      -- vim.ui.open(url) -- Neovim 0.10+
    end,

    follow_img_func = function(img)
      vim.fn.jobstart({ "qlmanage", "-p", img }) -- macOS Quick Look
      -- vim.fn.jobstart({ "xdg-open", img }) -- Linux
    end,

    -- ============================================================================
    -- Other Options
    -- ============================================================================
    open_notes_in = "current", -- "current", "vsplit", or "hsplit"
    disable_frontmatter = false,
    use_advanced_uri = false,
    open_app_foreground = false,
    log_level = vim.log.levels.INFO,
  },

  -- ============================================================================
  -- Additional Keymaps (Outside of obsidian.nvim config)
  -- ============================================================================
  config = function(_, opts)
    require("obsidian").setup(opts)

    -- SRS Commands
    vim.keymap.set("n", "<leader>osr", "<cmd>ObsidianSRSReview<cr>",
      { desc = "Start SRS review session" })
    vim.keymap.set("n", "<leader>osd", "<cmd>ObsidianSRSDue<cr>",
      { desc = "List due SRS cards" })
    vim.keymap.set("n", "<leader>oss", "<cmd>ObsidianSRSStats<cr>",
      { desc = "Show SRS statistics" })
    vim.keymap.set("n", "<leader>osb", "<cmd>ObsidianSRSBrowse<cr>",
      { desc = "Browse all SRS cards" })

    -- Note Commands
    vim.keymap.set("n", "<leader>on", "<cmd>ObsidianNew<cr>",
      { desc = "Create new note" })
    vim.keymap.set("n", "<leader>oq", "<cmd>ObsidianQuickSwitch<cr>",
      { desc = "Quick switch notes" })
    vim.keymap.set("n", "<leader>os", "<cmd>ObsidianSearch<cr>",
      { desc = "Search notes" })
    vim.keymap.set("n", "<leader>ot", "<cmd>ObsidianToday<cr>",
      { desc = "Open today's note" })
    vim.keymap.set("n", "<leader>oy", "<cmd>ObsidianYesterday<cr>",
      { desc = "Open yesterday's note" })
    vim.keymap.set("n", "<leader>ob", "<cmd>ObsidianBacklinks<cr>",
      { desc = "Show backlinks" })
    vim.keymap.set("n", "<leader>ol", "<cmd>ObsidianLinks<cr>",
      { desc = "Show all links" })
    vim.keymap.set("n", "<leader>op", "<cmd>ObsidianPasteImg<cr>",
      { desc = "Paste image" })
    vim.keymap.set("n", "<leader>oo", "<cmd>ObsidianOpen<cr>",
      { desc = "Open in Obsidian app" })
    vim.keymap.set("n", "<leader>og", "<cmd>ObsidianFollowLink<cr>",
      { desc = "Follow link" })
    vim.keymap.set("n", "<leader>oc", "<cmd>ObsidianToggleCheckbox<cr>",
      { desc = "Toggle checkbox" })
    vim.keymap.set("v", "<leader>oe", "<cmd>ObsidianExtractNote<cr>",
      { desc = "Extract to new note" })
    vim.keymap.set("v", "<leader>ol", "<cmd>ObsidianLink<cr>",
      { desc = "Link selection" })
    vim.keymap.set("v", "<leader>onl", "<cmd>ObsidianLinkNew<cr>",
      { desc = "Link to new note" })
  end,
}
