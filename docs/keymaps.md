# Keymaps

Neoweaver does not set any global keymaps by default. This page documents suggested keymaps and built-in buffer-local keymaps.

## Global Keymaps (User-Configured)

Add these to your Neovim configuration:

```lua
-- Notes
vim.keymap.set("n", "<leader>nl", "<cmd>NeoweaverNotesList<cr>", { desc = "List notes" })
vim.keymap.set("n", "<leader>nn", "<cmd>NeoweaverNotesNew<cr>", { desc = "New note" })
vim.keymap.set("n", "<leader>nN", "<cmd>NeoweaverNotesNewWithTitle<cr>", { desc = "New note with title" })
vim.keymap.set("n", "<leader>nt", "<cmd>NeoweaverNotesTitle<cr>", { desc = "Edit note title" })

-- Quicknotes
vim.keymap.set("n", "<leader>nq", "<cmd>NeoweaverNotesQuick<cr>", { desc = "Quick note" })
vim.keymap.set("n", "<leader>na", "<cmd>NeoweaverNotesQuickAmend<cr>", { desc = "Amend quicknote" })

-- Explorer
vim.keymap.set("n", "<leader>ne", "<cmd>NeoweaverExplorer<cr>", { desc = "Toggle explorer" })
```

### lazy.nvim

For lazy-loading on keypress:

```lua
{
  "nkapatos/neoweaver.nvim",
  keys = {
    { "<leader>nl", "<cmd>NeoweaverNotesList<cr>", desc = "List notes" },
    { "<leader>nn", "<cmd>NeoweaverNotesNew<cr>", desc = "New note" },
    { "<leader>nN", "<cmd>NeoweaverNotesNewWithTitle<cr>", desc = "New note with title" },
    { "<leader>nt", "<cmd>NeoweaverNotesTitle<cr>", desc = "Edit note title" },
    { "<leader>nq", "<cmd>NeoweaverNotesQuick<cr>", desc = "Quick note" },
    { "<leader>na", "<cmd>NeoweaverNotesQuickAmend<cr>", desc = "Amend quicknote" },
    { "<leader>ne", "<cmd>NeoweaverExplorer<cr>", desc = "Toggle explorer" },
  },
  -- ... rest of config
}
```

## Explorer Keymaps

These keymaps are active in the explorer sidebar:

| Key | Action | Description |
|-----|--------|-------------|
| `<CR>` | Select | Open note or expand/collapse collection |
| `o` | Select | Same as `<CR>` |
| `a` | Create | Create note or collection (append `/` for collection) |
| `r` | Rename | Rename collection (not available for notes) |
| `d` | Delete | Delete note or collection |

### Create Convention

When pressing `a` to create:
- `meeting notes` creates a **note** named "meeting notes"
- `projects/` creates a **collection** named "projects"

## Conflict Resolution Keymaps

These keymaps are active when a save conflict is detected (412 Precondition Failed):

| Key | Action | Description |
|-----|--------|-------------|
| `]c` | Next conflict | Jump to next unresolved conflict |
| `[c` | Previous conflict | Jump to previous unresolved conflict |
| `gh` | Accept server | Use server version, discard local changes |
| `gl` | Keep local | Keep local version, discard server changes |
| `gb` | Keep both | Insert both versions with markers |

After resolving conflicts, save with `:w` to retry.

## Floating Picker Keymaps

These keymaps are active in floating picker windows (e.g., note list):

| Key | Action |
|-----|--------|
| `<CR>` | Select item |
| `q` | Close picker |
| `<Esc>` | Close picker |

## See Also

- [Commands](commands.md) - Full list of available commands
- [Configuration](configuration.md) - Plugin configuration options
