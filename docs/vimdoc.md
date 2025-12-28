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

For detailed API documentation including function signatures, parameters, and types, see:

`:help neoweaver-api`

The API reference is auto-generated from source code annotations and includes documentation for:

- `require('neoweaver').setup()` - Plugin configuration
- Internal modules and functions
- Type definitions

# See Also

- Plugin repository: https://github.com/nkapatos/neoweaver.nvim
- MindWeaver server: https://github.com/nkapatos/mindweaver
