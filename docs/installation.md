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

## Next Steps

- See [Keymaps](keymaps.md) for suggested keymaps and built-in mappings
- See [Commands](commands.md) for the full list of available commands
- See [Configuration](configuration.md) for all configuration options
