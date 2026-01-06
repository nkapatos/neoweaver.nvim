# Installation

## Prerequisites

- **Neovim 0.11+** - Required for plugin functionality
- **[plenary.nvim](https://github.com/nvim-lua/plenary.nvim)** - Required dependency for HTTP requests
- **[nui.nvim](https://github.com/MunifTanjim/nui.nvim)** - Required dependency for UI components
- **MindWeaver server** - Running and accessible

## Plugin Setup

### lazy.nvim

```lua
{
  "nkapatos/neoweaver.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
  },
  opts = {
    api = {
      servers = {
        local = { url = "http://localhost:9421", default = true },
      },
    },
  },
}
```

### vim.pack (Neovim 0.12+)

```lua
vim.pack.add({
  url = "https://github.com/nkapatos/neoweaver.nvim",
  dependencies = {
    { url = "https://github.com/nvim-lua/plenary.nvim" },
    { url = "https://github.com/MunifTanjim/nui.nvim" },
  },
})

require('neoweaver').setup({
  api = {
    servers = {
      local = { url = "http://localhost:9421", default = true },
    },
  },
})
```

### packer.nvim

```lua
use {
  "nkapatos/neoweaver.nvim",
  requires = {
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
  },
  config = function()
    require('neoweaver').setup({
      api = {
        servers = {
          local = { url = "http://localhost:9421", default = true },
        },
      },
    })
  end,
}
```

## Keymaps

Neoweaver does not set any keymaps by default. Copy the keymaps you want to your configuration:

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

For lazy.nvim users, you can use the `keys` table for lazy-loading on keypress:

```lua
{
  "nkapatos/neoweaver.nvim",
  keys = {
    { "<leader>nl", "<cmd>NeoweaverNotesList<cr>", desc = "List notes" },
    { "<leader>nn", "<cmd>NeoweaverNotesNew<cr>", desc = "New note" },
    -- add more as needed
  },
  -- ... rest of config
}
```

## Next Steps

- See [Commands](commands.md) for the full list of available commands
- See [Configuration](configuration.md) for all configuration options
