# obsidian.nvim

A Neovim plugin for writing and navigating [Obsidian](https://obsidian.md) vaults.

## Installation

### Requirements

- Neovim >= 0.8.0
- [ripgrep](https://github.com/BurntSushi/ripgrep) (for search/completion)

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
return {
  "epwalsh/obsidian.nvim",
  version = "*",
  lazy = true,
  ft = "markdown",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "hrsh7th/nvim-cmp",
    "nvim-telescope/telescope.nvim",
  },
  opts = {
    workspaces = {
      {
        name = "personal",
        path = "~/Documents/Notes",
      },
    },
  },
}
```

**For a complete configuration with all options, see [`lazy-obsidian-example.lua`](./lazy-obsidian-example.lua)**

## Commands & Shortcuts

### Notes

| Command | Shortcut | Description |
|---------|----------|-------------|
| `:ObsidianNew` | `<leader>on` | Create new note |
| `:ObsidianQuickSwitch` | `<leader>oq` | Quick switch between notes |
| `:ObsidianSearch` | `<leader>os` | Search notes |
| `:ObsidianOpen` | `<leader>oo` | Open in Obsidian app |
| `:ObsidianFollowLink` | `gf` or `<leader>og` | Follow link under cursor |
| `:ObsidianBacklinks` | `<leader>ob` | Show backlinks to current note |
| `:ObsidianLinks` | `<leader>ol` | List all links in current note |

### Daily Notes

| Command | Shortcut | Description |
|---------|----------|-------------|
| `:ObsidianToday` | `<leader>ot` | Open/create today's note |
| `:ObsidianYesterday` | `<leader>oy` | Open yesterday's note |
| `:ObsidianTomorrow` | - | Open tomorrow's note |
| `:ObsidianDailies` | - | List daily notes |

### Editing

| Command | Shortcut | Description |
|---------|----------|-------------|
| `:ObsidianToggleCheckbox` | `<leader>oc` or `<leader>ch` | Toggle checkbox |
| `:ObsidianPasteImg` | `<leader>op` | Paste image from clipboard |
| `:ObsidianTemplate` | - | Insert template |
| `:ObsidianRename` | - | Rename note and update backlinks |

### SRS (Spaced Repetition)

| Command | Shortcut | Description |
|---------|----------|-------------|
| `:ObsidianSRSReview` | `<leader>osr` | Start flashcard review session |
| `:ObsidianSRSDue` | `<leader>osd` | List due cards |
| `:ObsidianSRSStats` | `<leader>oss` | Show review statistics |
| `:ObsidianSRSBrowse` | `<leader>osb` | Browse all cards |

#### Card Format

```markdown
Question :: Answer

Question ::: Answer    (reversed card - both directions)

{{c1::cloze deletion}} (cloze card)
```

## Quick Start

1. Install the plugin with lazy.nvim
2. Configure your vault path in the `workspaces` option
3. Use `<leader>on` to create notes, `<leader>osr` to review flashcards
4. Type `[[` to link to other notes with autocomplete

## Configuration

See [`lazy-obsidian-example.lua`](./lazy-obsidian-example.lua) for a complete example including:
- Workspace setup
- SRS (spaced repetition) configuration
- UI customization
- Key mappings
- Templates and daily notes
