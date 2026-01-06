# Architecture

Developer documentation for neoweaver internals.

## Module Structure

```
lua/neoweaver/
  init.lua              # Public API, lazy loading, ensure_ready
  types.lua             # Auto-generated types from proto
  health.lua            # :checkhealth integration

lua/neoweaver/_internal/
  config.lua            # Configuration management
  api.lua               # HTTP client, SSE events
  server_selector.lua   # Server picker for health failures
  notes.lua             # Note CRUD operations
  quicknote.lua         # Ephemeral capture popup
  collections.lua       # Collection CRUD operations
  tags.lua              # Tag listing (read-only)
  diff.lua              # Conflict resolution overlay
  
  meta/                 # Metadata extraction
    init.lua            # Public API
    extractor.lua       # .weaveroot.json parsing
    weaverc.lua         # .weaverc.json parsing
    parsers.lua         # JSON/YAML/TOML parsers
  
  buffer/               # Buffer management
    manager.lua         # Entity-buffer lifecycle
    statusline.lua      # Window statusline
  
  picker/               # Tree picker component
    init.lua            # Picker class
    manager.lua         # ViewSource registry
    configs.lua         # Host-specific keymaps
    types.lua           # Type definitions
  
  explorer/             # Sidebar host
    init.lua            # Split window management
  
  collections/          # Collection domain
    view.lua            # ViewSource implementation
  
  tags/                 # Tag domain
    view.lua            # ViewSource implementation
```

## Initialization Flow

```
User calls setup(opts)
        │
        ▼
Store opts in _pending_opts
(no initialization yet)
        │
        ▼
User triggers a command
        │
        ▼
ensure_ready(on_ready, on_cancel)
        │
        ▼
First time? ──yes──▶ do_init()
        │              ├─ config.apply(opts)
        │              ├─ api.setup(opts.api)
        │              ├─ notes.setup()
        │              └─ require views (self-register)
        │
        ▼
api.health.ping(current_server)
        │
        ├─ healthy ──▶ _initialized = true ──▶ on_ready()
        │
        └─ unhealthy ──▶ server_selector.show()
                              │
                              ├─ user selects ──▶ retry ping
                              └─ user cancels ──▶ on_cancel()
```

## API Layer

### Connect RPC

The MindWeaver server uses Connect RPC (gRPC-compatible over HTTP).

- All requests use POST regardless of semantic method
- Success returns proto message directly (no wrapper)
- Errors return `{"code": "...", "message": "...", "details": [...]}`
- ETags used for optimistic locking on updates

### Service Endpoints

**Notes Service**
| Endpoint | Request | Response |
|----------|---------|----------|
| `/mind.v3.NotesService/ListNotes` | ListNotesRequest | ListNotesResponse |
| `/mind.v3.NotesService/GetNote` | GetNoteRequest | Note |
| `/mind.v3.NotesService/CreateNote` | CreateNoteRequest | Note |
| `/mind.v3.NotesService/NewNote` | NewNoteRequest | Note |
| `/mind.v3.NotesService/FindNotes` | FindNotesRequest | FindNotesResponse |
| `/mind.v3.NotesService/ReplaceNote` | ReplaceNoteRequest | Note (If-Match required) |
| `/mind.v3.NotesService/UpdateNote` | UpdateNoteRequest | Note (If-Match required) |
| `/mind.v3.NotesService/DeleteNote` | DeleteNoteRequest | Empty |

**Collections Service**
| Endpoint | Request | Response |
|----------|---------|----------|
| `/mind.v3.CollectionsService/ListCollections` | ListCollectionsRequest | ListCollectionsResponse |
| `/mind.v3.CollectionsService/GetCollection` | GetCollectionRequest | Collection |
| `/mind.v3.CollectionsService/CreateCollection` | CreateCollectionRequest | Collection |
| `/mind.v3.CollectionsService/UpdateCollection` | UpdateCollectionRequest | Collection |
| `/mind.v3.CollectionsService/DeleteCollection` | DeleteCollectionRequest | Empty |

**Tags Service**
| Endpoint | Request | Response |
|----------|---------|----------|
| `/mind.v3.TagsService/ListTags` | ListTagsRequest | ListTagsResponse |

### Server-Sent Events (SSE)

Real-time updates via SSE connection to `/events`.

**Event Format**
```
id: 42
event: note
data: {"type":"updated","entity_id":123,"ts":1735748041321}

```

**Event Types**: `note`, `collection`, `tag`, `system`

**Subscription API**
```lua
local unsubscribe = api.events.on(api.events.types.NOTE, function(event)
  -- handle event
end)

-- MUST call on cleanup to prevent memory leaks
unsubscribe()
```

**Self-Event Filtering**: Events originating from this session are skipped via `origin_session_id` comparison. Session ID assigned on SSE connect, sent via `X-Session-Id` header on requests.

**plenary.curl Gotchas**
- Use `raw = { "-N" }` to disable curl buffering
- Stream callback strips newlines; reconstruct for SSE parsing

## Buffer Management

### Design Principles

- Domain-agnostic: no notes-specific logic in manager
- Type-based handlers: register `on_save`/`on_close` per entity type
- Bidirectional lookup: bufnr ↔ entity

### State

```lua
M.state = {
  buffers = {},   -- bufnr → { type, id, data }
  index = {},     -- "type:id" → bufnr
  handlers = {},  -- type → { on_save, on_close }
}
```

### Window Selection

When opening a buffer, `find_target_window()`:
1. Uses current window if normal file (not explorer/terminal/float)
2. Finds most recently used suitable window
3. Falls back to vertical split from explorer

## Picker Architecture

See [picker-architecture.md](picker-architecture.md) for the ViewSource contract and design decisions.

## Open Issues

Reference these when working on related code:

- **#7** - Pagination not implemented for collections/notes listing
- **#10** - Conflict resolution "both" format may need refinement
- **#13** - Quicknote payload configuration
- **#14** - Quicknote amend/list features
- **#15** - Metadata editing UI
- **#24** - Note finder pending picker refactor
