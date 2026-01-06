<!-- panvimdoc-ignore-start -->
<p align="center">
  <img src="assets/logo.svg" alt="Neoweaver" width="120" />
</p>
<!-- panvimdoc-ignore-end -->

# Neoweaver

### Neovim client for [MindWeaver](https://github.com/nkapatos/mindweaver)

<!-- panvimdoc-ignore-start -->
---

[![CI](https://img.shields.io/github/actions/workflow/status/nkapatos/neoweaver.nvim/pr-checks.yml?branch=main&style=flat-square&logo=github&label=CI)](https://github.com/nkapatos/neoweaver.nvim/actions/workflows/pr-checks.yml)
[![Release](https://img.shields.io/github/v/release/nkapatos/neoweaver.nvim?style=flat-square&logo=github)](https://github.com/nkapatos/neoweaver.nvim/releases/latest)
[![Neovim](https://img.shields.io/badge/Neovim-0.11+-57A143?style=flat-square&logo=neovim)](https://github.com/neovim/neovim/releases/tag/v0.11.0)

> Your second brain, one keystroke away — no mouse required, sanity preserved.
<!-- panvimdoc-ignore-end -->

Neoweaver brings MindWeaver's personal knowledge management directly into Neovim. Create, browse, and search your notes without leaving your editor, communicating with the MindWeaver server over the Connect RPC API.

## Installation

### lazy.nvim

```lua
{
  "nkapatos/neoweaver.nvim",
  cmd = { "NeoweaverNotesList", "NeoweaverNotesNew", "NeoweaverNotesQuick" },
  dependencies = {
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
  },
  opts = {
    api = {
      -- URLs where your MindWeaver server is running
      servers = {
        local = { url = "http://localhost:9421", default = true },
        cloud = { url = "https://mindweaver.example.com" },
      },
    },
  },
}
```

### vim.pack() (Neovim 0.12+)

```lua
vim.pack({
  name = "neoweaver",
  url = "https://github.com/nkapatos/neoweaver.nvim",
  dependencies = {
    { url = "https://github.com/nvim-lua/plenary.nvim" },
    { url = "https://github.com/MunifTanjim/nui.nvim" },
  },
})

require('neoweaver').setup({
  api = {
    -- URLs where your MindWeaver server is running
    servers = {
      local = { url = "http://localhost:9421", default = true },
      cloud = { url = "https://mindweaver.example.com" },
    },
  },
})
```

See [docs/installation.md](docs/installation.md) for additional configuration options.

## Quick Start

Suggested keymaps (not set by default):

| Keymap | Action |
|--------|--------|
| `<leader>nl` | List notes |
| `<leader>nn` | New note |
| `<leader>nt` | Edit note title |
| `<leader>nq` | Quick capture |
| `<leader>ne` | Toggle explorer |

Key commands:

```vim
:NeoweaverNotesList      " Browse your notes
:NeoweaverNotesNew       " Create a new note
:NeoweaverNotesQuick     " Capture a quick thought
:NeoweaverServerUse      " Switch server
```

See [docs/keymaps.md](docs/keymaps.md) and [docs/commands.md](docs/commands.md) for the full reference.

## Documentation

- [Installation](docs/installation.md)
- [Configuration](docs/configuration.md)
- [Commands](docs/commands.md)
- [Keymaps](docs/keymaps.md)

Or use `:help neoweaver` inside Neovim.

## Requirements

- **Neovim 0.11+**
- **MindWeaver server** — see [MindWeaver](https://github.com/nkapatos/mindweaver) to get started
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [nui.nvim](https://github.com/MunifTanjim/nui.nvim)
