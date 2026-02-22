# obsidian.nvim

A lightweight Neovim companion designed to supercharge your **Obsidian** workflow with focus-driven task management and spaced-repetition flashcards.

> [!IMPORTANT]
> **Philosophy**: Standard Markdown navigation (links, backlinks, rename, tags) and completion are now handled by the [markdown-oxide](https://github.com/Feel-Free/markdown-oxide) LSP. This plugin serves as a specialized engine for Task automation and SRS.

---

## 🚀 Core Pillar 1: Focus-Driven Tasks

Enforce a "One Thing at a Time" philosophy with built-in time tracking and vault-wide synchronization.

### 🎯 The Workflow
1. **Prioritize**: Use `#p1` (Critical), `#p2` (High), or `#p3` (Normal).
2. **Focus**: Run `:ObsidianTaskToggle`. Starting a task (`[/]`) automatically **pauses** any other active task in your vault.
3. **Log**: Every session is logged with precision in blockquotes.
4. **Dashboard**: Use `:ObsidianTaskDashboard` for a unified view of your focus and "starving" projects.

### 📊 Daily Statistics & Auto-Updates
Integrate work summaries into your Daily Notes:
- **Live Placeholder**: Add `<!-- obsidian-task-stats -->` to your note. It refreshes automatically on every save.
- **Templates**: Use `{{task_stats}}` in your Daily Note template.

### 🗂️ Task States
| State | Syntax | Description |
|-------|--------|-------------|
| **Todo** | `[ ]` | Not started. |
| **Active** | `[/]` | Currently focused. Timer is running. |
| **Paused** | `[|]` | Work in progress, temporarily stopped. |
| **Blocked** | `[?]` | Waiting on external dependencies. |
| **Done** | `[x]` | Completed. Final time summary written. |

---

## 🧠 Core Pillar 2: Spaced Repetition (SRS)

A powerful flashcard system using the **SM2 algorithm**, built directly into your notes.

### 🗃️ Card Formats
```markdown
# Basic Card
Question :: Answer

# Reversed Card (Tests both directions)
Front ::: Back

# Cloze Deletion
{{c1::Neovim}} is a text editor.
```

### ⚡ Commands
- `:ObsidianSRSReview`: Start a review session.
- `:ObsidianSRSStats`: View your learning progress.
- `:ObsidianSRSBrowse`: Search and manage your card deck.

---

## 🛠️ Installation & Setup

### Requirements
- Neovim >= 0.8.0
- [ripgrep](https://github.com/BurntSushi/ripgrep) (Required for Task Dashboard and Stats)
- **[markdown-oxide](https://github.com/Feel-Free/markdown-oxide)** (Required for navigation/completion)

### Example Configuration (lazy.nvim)
```lua
return {
  "abhisheksatyam123/obsidian.nvim_abhi",
  dependencies = { "nvim-lua/plenary.nvim" },
  opts = {
    workspaces = {
      { name = "vault", path = "~/Documents/Notes" },
    },
    tasks = {
      enabled = true,
      auto_pause_on_exit = true,
      daily_stats_placeholder = "<!-- obsidian-task-stats -->",
    },
  },
}
```

---

## 🔌 Partner LSP: markdown-oxide

To get the full Obsidian experience (linking, backlinks, rename, autocomplete), you **must** configure `markdown-oxide`.

For a complete, copy-pasteable configuration including smart link following and daily note commands, see [**`markdown-oxide-lsp-example.lua`**](./markdown-oxide-lsp-example.lua).

---

## 📖 Complete Documentation
For recommended keybindings and a full list of settings, see:
- [**`lazy-obsidian-example.lua`**](./lazy-obsidian-example.lua) (Plugin Config)
- [**`markdown-oxide-lsp-example.lua`**](./markdown-oxide-lsp-example.lua) (LSP Config)
