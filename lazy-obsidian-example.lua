-- ============================================================================
-- Lazy.nvim Configuration for obsidian.nvim
-- ============================================================================
-- Copy this file to your Neovim configuration: ~/.config/nvim/lua/plugins/obsidian.lua
-- or nvim/lua/plugins/obsidian.lua (depending on your setup)
--
-- This configuration includes:
-- - Basic vault/workspace setup
-- - SRS (Spaced Repetition System) for flashcard reviews
-- - UI concealment and frontmatter management
-- - Templates, daily notes, and image paste
-- ============================================================================

return {
  "abhisheksatyam123/obsidian.nvim_abhi",
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

    -- Recommended: LSP and Syntax
    -- Use https://github.com/Feel-Free/markdown-oxide for best experience
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
    -- Task Management & Time Tracking
    -- ============================================================================
    -- Org-mode style task management with time tracking and vault-wide dashboards.
    -- Checkbox states: [ ] Todo, [/] Active, [|] Paused, [?] Blocked, [-] Cancelled, [x] Done
    tasks = {
      enabled = true,                  -- Enable task management commands
      auto_pause_on_exit = true,       -- Auto-pause active [/] tasks when quitting Neovim
      stale_threshold_days = 3,        -- Days before a project is flagged as "starving"
      daily_stats_placeholder = "<!-- obsidian-task-stats -->",
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
        ["/"] = { char = "🟢", hl_group = "ObsidianActive" },
        ["|"] = { char = "⏸", hl_group = "ObsidianPaused" },
        ["?"] = { char = "🚧", hl_group = "ObsidianBlocked" },
        ["-"] = { char = "❌", hl_group = "ObsidianCancelled" },
        ["x"] = { char = "✅", hl_group = "ObsidianDone" },
        [">"] = { char = "", hl_group = "ObsidianRightArrow" },
        ["~"] = { char = "󰰱", hl_group = "ObsidianTilde" },
        ["!"] = { char = "", hl_group = "ObsidianImportant" },
      },

      bullets = { char = "•", hl_group = "ObsidianBullet" },
      external_link_icon = { char = "", hl_group = "ObsidianExtLinkIcon" },
      reference_text = { hl_group = "ObsidianRefText" },
      highlight_text = { hl_group = "ObsidianHighlightText" },
      tags = { hl_group = "ObsidianTag" },
      block_ids = { hl_group = "ObsidianBlockID" },

      hl_groups = {
        ObsidianTodo = { bold = true, fg = "#f78c6c" },
        ObsidianActive = { bold = true, fg = "#89ddff" },
        ObsidianPaused = { bold = true, fg = "#ffcb6b" },
        ObsidianBlocked = { bold = true, fg = "#ff5370" },
        ObsidianCancelled = { bold = true, fg = "#676e95" },
        ObsidianDone = { bold = true, fg = "#c3e88d" },
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

    vim.keymap.set("n", "<leader>op", "<cmd>ObsidianPasteImg<cr>",
      { desc = "Paste image" })
    vim.keymap.set("n", "<leader>oo", "<cmd>ObsidianOpen<cr>",
      { desc = "Open in Obsidian app" })
    -- Note navigation is handled by markdown-oxide LSP (gf, <CR>).
    -- See markdown-oxide-lsp-example.lua for recommended LSP setup.

    -- Task Management Commands
    vim.keymap.set("n", "<leader>ott", "<cmd>ObsidianTaskToggle<cr>",
      { desc = "Smart-toggle task state" })
    vim.keymap.set("n", "<leader>otd", "<cmd>ObsidianTaskToggle done<cr>",
      { desc = "Mark task done" })
    vim.keymap.set("n", "<leader>otb", "<cmd>ObsidianTaskToggle blocked<cr>",
      { desc = "Mark task blocked" })
    vim.keymap.set("n", "<leader>otc", "<cmd>ObsidianTaskToggle cancel<cr>",
      { desc = "Cancel task" })
    vim.keymap.set("n", "<leader>otp", "<cmd>ObsidianTaskPauseAll<cr>",
      { desc = "Pause all active tasks" })
    vim.keymap.set("n", "<leader>tp", "<cmd>ObsidianTaskPriority<cr>",
      { desc = "Cycle task priority" })
    vim.keymap.set("n", "<leader>otD", "<cmd>ObsidianTaskDashboard<cr>",
      { desc = "Open task dashboard" })
    vim.keymap.set("n", "<leader>ots", "<cmd>ObsidianTaskStats<cr>",
      { desc = "Insert daily work summary" })

    -- ============================================================================
    -- Partner LSP: markdown-oxide
    -- ============================================================================
    -- To get the full Obsidian experience (linking, backlinks, rename, autocomplete),
    -- you must configure the markdown-oxide LSP.
    --
    -- Example setup using nvim-lspconfig:
    --
    -- local lspconfig = require('lspconfig')
    -- lspconfig.markdown_oxide.setup({
    --   capabilities = capabilities, -- Your standard capabilities
    --   on_attach = on_attach,       -- Your standard on_attach
    --   root_dir = lspconfig.util.root_pattern('.obsidian', 'obsidian.json', '.git'),
    -- })

  end,
}
