# Configuration

## Configuration Options

### allow_multiple_empty_notes

- **Type:** boolean
- **Default:** `false`

When `true`, new note buffers are marked as modified immediately, allowing multiple untitled notes without Neovim blocking on `:w`.

```lua
require('neoweaver').setup({
  allow_multiple_empty_notes = true,
})
```

### api.servers

- **Type:** table (required)
- **Description:** Map of server names to configuration

Each server entry must provide a `url`. Set `default = true` on one entry to select it automatically.

**Single server example:**

```lua
api = {
  servers = {
    local = { url = "http://localhost:9421", default = true },
  },
}
```

**Multiple servers example:**

```lua
api = {
  servers = {
    local = { url = "http://localhost:9421", default = true },
    cloud = { url = "https://mindweaver.example.com" },
    staging = { url = "https://staging.mindweaver.example.com" },
  },
}
```

Switch between servers using `:NeoweaverServerUse <server_name>`.

### api.debug_info

- **Type:** boolean
- **Default:** `true`

Toggles API request/response logging. Can be toggled at runtime with `:NeoweaverToggleDebug`.

```lua
api = {
  debug_info = false,  -- Disable debug logging
}
```

### quicknotes

- **Type:** table
- **Default:** see below

Quicknotes configure the floating capture window. The default configuration matches the built-in capture flow:

```lua
quicknotes = {
  title_template = "%Y%m%d%H%M",
  collection_id = 2,
  note_type_id = 2,
  popup = {
    relative = "editor",
    position = "50%",
    size = {
      width = "40%",
      height = "20%",
    },
    border = {
      style = "rounded",
      text = {
        top = "Quick Note",
        top_align = "center",
      },
    },
  },
}
```

Notes:

- `title_template` is passed to `strftime()` when a quicknote saves. Use any valid strftime pattern.
- `collection_id` and `note_type_id` use default values and are not yet user-configurable.

### explorer

- **Type:** table
- **Default:** `{ show_notifications = true, position = "left", size = 30 }`

Controls explorer sidebar behavior and appearance.

```lua
explorer = {
  show_notifications = true,  -- Show notifications on refresh
  position = "left",          -- "left" or "right"
  size = 30,                  -- Width of the explorer sidebar
}
```

### picker

- **Type:** table
- **Default:** see below

Controls floating picker appearance (e.g., note list picker).

```lua
picker = {
  size = {
    width = 60,
    height = 20,
  },
  position = "50%",
  border = {
    style = "rounded",
  },
}
```

### metadata

Metadata is automatically extracted and attached to notes when saving. No configuration required.

#### Auto-detected fields

The following fields are captured automatically:

| Field | Description |
|-------|-------------|
| `project` | From `.weaveroot.json` `meta.project`, or directory name fallback |
| `project_root` | Absolute path to project root (where `.weaveroot.json` lives) |
| `cwd` | Current working directory of the nvim session |
| `commit_hash` | Git short hash (`git rev-parse --short HEAD`) |
| `git_branch` | Current git branch (`git branch --show-current`) |

#### .weaveroot.json meta

Additional project-level metadata can be defined in `.weaveroot.json`:

```json
{
  "meta": {
    "project": "Mindweaver",
    "author": "Your Name",
    "team": "Core"
  }
}
```

All fields under `meta` are merged with auto-detected fields. `meta` fields override auto-detected ones (e.g., `meta.project` overrides the directory name).

### Project Files

#### .weaveroot / .weaveroot.json

Marks the project root boundary. The extractor walks up from cwd until it finds one of these files.

- `.weaveroot` - Empty file, only marks the boundary
- `.weaveroot.json` - Marks the boundary AND provides project metadata via the `meta` key

If neither is found, session cwd is used as the project root.

```json
{
  "meta": {
    "project": "my-workspace",
    "description": "Parent workspace for multiple projects"
  }
}
```

#### .weaverc.json

Project-level plugin settings (NOT metadata). Used to configure plugin behavior per-directory, such as default collection, template, or server.

```json
{
  "settings": {
    "collection_id": 5,
    "template": "daily",
    "server": "work"
  }
}
```

Note: `.weaverc.json` does NOT contribute to note metadata. Only `.weaveroot.json` provides project metadata.

## Complete Setup Example

```lua
require('neoweaver').setup({
  allow_multiple_empty_notes = true,
  explorer = {
    position = "left",
    size = 30,
  },
  quicknotes = {
    title_template = "%Y%m%d%H%M",
    popup = {
      size = {
        width = 80,
        height = 20,
      },
      border = {
        text = {
          top = "Scratchpad",
        },
      },
    },
  },
  api = {
    servers = {
      local = { url = "http://localhost:9421", default = true },
      cloud = { url = "https://mindweaver.example.com" },
    },
    debug_info = true,
  },
})
```

For keymaps configuration, see [Keymaps](keymaps.md).
