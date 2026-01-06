# Keymaps

Neoweaver does not set any keymaps by default. See [Installation](installation.md#keymaps) for setup instructions.

## Suggested Keymaps

```lua
-- Notes
vim.keymap.set("n", "<leader>nl", "<cmd>NeoweaverNotesList<cr>", { desc = "List notes" })
vim.keymap.set("n", "<leader>nn", "<cmd>NeoweaverNotesNew<cr>", { desc = "New note" })
vim.keymap.set("n", "<leader>nN", "<cmd>NeoweaverNotesNewWithTitle<cr>", { desc = "New note with title" })
vim.keymap.set("n", "<leader>nt", "<cmd>NeoweaverNotesTitle<cr>", { desc = "Edit note title" })

-- Quicknotes
vim.keymap.set("n", "<leader>qn", "<cmd>NeoweaverNotesQuick<cr>", { desc = "Quick note" })
vim.keymap.set("n", "<leader>qa", "<cmd>NeoweaverNotesQuickAmend<cr>", { desc = "Amend quicknote" })

-- Explorer
vim.keymap.set("n", "<leader>ne", "<cmd>NeoweaverExplorer<cr>", { desc = "Toggle explorer" })
```

## All Available Commands

See [Commands](commands.md) for the complete list of commands you can map.
