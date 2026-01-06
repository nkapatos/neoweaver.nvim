# Neoweaver

Neovim client for MindWeaver - Manage your notes directly from Neovim.

## Introduction

Neoweaver is a Neovim plugin that provides note management capabilities by communicating with the MindWeaver server over the Connect RPC API. It allows you to create, edit, and organize notes directly within Neovim using markdown buffers.

```{.include}
docs/installation.md
```

```{.include}
docs/configuration.md
```

```{.include}
docs/commands.md
```

```{.include}
docs/keymaps.md
```

# API Reference

For detailed API documentation including function signatures, parameters, and types, see the `neoweaver_api.txt` help file:

- `:help M.setup()` - Plugin configuration
- `:help M.ensure_ready()` - Initialization entry point
- `:help M.get_config()` - Get current configuration
- `:help M.get_explorer()` - Get explorer instance

# See Also

- Plugin repository: https://github.com/nkapatos/neoweaver.nvim
- MindWeaver server: https://github.com/nkapatos/mindweaver
