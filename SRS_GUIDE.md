# Spaced Repetition System (SRS) - Quick Reference

## Overview

This fork of obsidian.nvim includes a built-in Spaced Repetition System (SRS) for reviewing flashcards directly in Neovim. It's compatible with the Obsidian Spaced Repetition community plugin format.

## Card Format

### Basic Card (Question → Answer)
```markdown
What is the capital of France? :: Paris
```

### Reversed Card (Bidirectional)
```markdown
English: Hello ::: Spanish: Hola
```
Use `:::` (three colons) to create a card that asks both directions (answer first, then question).

### With Scheduling Data
After reviewing, cards will have scheduling data appended:
```markdown
What is the capital of France? :: Paris <!--SR:!2025-02-15,3,250-->
```
Format: `<!--SR:!YYYY-MM-DD,interval,ease-->`

## Commands

| Command | Description |
|---------|-------------|
| `:ObsidianSRSReview` | Start reviewing all due cards in a floating window |
| `:ObsidianSRSDue` | List all due cards in your picker (Telescope/fzf-lua) |

### Keybindings in Review Mode

| Key | Action |
|-----|--------|
| `<Space>` or `<CR>` | Reveal answer / question |
| `1` | Again (reset card) |
| `2` | Hard |
| `3` | Good |
| `4` | Easy |
| `q` or `<Esc>` | Quit review |

## Configuration

Add SRS options to your obsidian.nvim config:

```lua
{
  -- ... other options ...
  
  srs = {
    enabled = true,              -- Enable/disable SRS commands
    max_new_per_day = 20,        -- Max new cards per review session
    max_reviews_per_day = 100,   -- Max total reviews per session
    default_ease = 2.5,          -- Starting ease factor
    min_ease = 1.3,              -- Minimum ease factor
    easy_bonus = 1.3,            -- Multiplier for "easy" responses
    hard_interval = 1.2,         -- Multiplier for "hard" responses
  },
}
```

## Algorithm

Uses the **SM-2 algorithm** (same as Anki and the Obsidian Spaced Repetition plugin):

- **Grade 1 (Again)**: Reset card, interval = 1 day, decrease ease
- **Grade 3 (Hard)**: Small interval increase, slightly decrease ease
- **Grade 4 (Good)**: Normal interval increase
- **Grade 5 (Easy)**: Large interval increase, increase ease

## Safety Features

- **Unsaved Changes Detection**: SRS will not modify files with unsaved buffer changes
- **Error Logging**: Clear error messages if file operations fail

## Tips

1. Create cards throughout your notes using `::` or `:::`
2. Run `:ObsidianSRSReview` daily to review due cards
3. Use `:ObsidianSRSDue` to preview what's due
4. Cards are plain text - sync your vault to any device

## Troubleshooting

**"Cannot update card: file has unsaved changes"**
→ Save the file first with `:w`

**"No cards due for review!"**
→ Either no cards are due, or ripgrep isn't finding them. Check that your cards use `::` or `:::` syntax.

**Cards not appearing**
→ Make sure ripgrep is installed and on your PATH
