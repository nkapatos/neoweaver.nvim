# Commands

Neoweaver provides commands for managing notes, quicknotes, collections, and server configuration.

## Notes

| Command | Arguments | Description |
|---------|-----------|-------------|
| `:NeoweaverNotesList` | - | List notes in picker |
| `:NeoweaverNotesOpen` | `<id>` | Open note by ID |
| `:NeoweaverNotesNew` | - | Create new untitled note |
| `:NeoweaverNotesNewWithTitle` | - | Create note with title prompt |
| `:NeoweaverNotesTitle` | - | Edit current note title |
| `:NeoweaverNotesDelete` | `<id>` | Delete note by ID |
| `:NeoweaverNotesMeta` | `[id]` | Edit note metadata (WIP - See issue #15) |

## Quicknotes

| Command | Arguments | Description |
|---------|-----------|-------------|
| `:NeoweaverNotesQuick` | - | Capture quicknote in floating window |
| `:NeoweaverNotesQuickAmend` | - | Amend last quicknote (WIP - See issue #14) |
| `:NeoweaverNotesQuickList` | - | List quicknotes (WIP - See issue #14) |

## Explorer & Collections

| Command | Arguments | Description |
|---------|-----------|-------------|
| `:NeoweaverExplorer` | `[action]` | Explorer (open/close/toggle/focus) |
| `:NeoweaverCollectionCreate` | `<name> [parent_id]` | Create new collection |
| `:NeoweaverCollectionRename` | `<id> <new_name>` | Rename collection |
| `:NeoweaverCollectionDelete` | `<id>` | Delete collection (prompts for confirmation) |
| `:NeoweaverCollectionUpdate` | `<id> [key=val...]` | Update collection fields |

## Server

| Command | Arguments | Description |
|---------|-----------|-------------|
| `:NeoweaverServerUse` | `<name>` | Switch to configured server |
| `:NeoweaverToggleDebug` | - | Toggle debug logging |

## Usage Examples

### Creating Notes

```vim
" Create a new untitled note
:NeoweaverNotesNew

" Create a note with title prompt
:NeoweaverNotesNewWithTitle

" Capture a quicknote (floating window)
:NeoweaverNotesQuick
```

### Managing Notes

```vim
" List all notes in picker
:NeoweaverNotesList

" Open a specific note by ID
:NeoweaverNotesOpen 42

" Edit the title of the current note
:NeoweaverNotesTitle

" Delete a note by ID
:NeoweaverNotesDelete 42
```

### Explorer & Collections

```vim
" Toggle the explorer panel
:NeoweaverExplorer

" Open/close/focus explorer explicitly
:NeoweaverExplorer open
:NeoweaverExplorer close
:NeoweaverExplorer focus

" Create a new collection
:NeoweaverCollectionCreate MyCollection

" Create a nested collection (with parent ID)
:NeoweaverCollectionCreate SubCollection 5

" Rename a collection
:NeoweaverCollectionRename 5 NewName

" Update collection fields
:NeoweaverCollectionUpdate 5 displayName=NewName parentId=2

" Delete a collection
:NeoweaverCollectionDelete 5
```

### Server Management

```vim
" Switch to a different configured server
:NeoweaverServerUse cloud

" Toggle debug logging
:NeoweaverToggleDebug
```

## Conflict Resolution

When saving a note and the server version has changed (412 Precondition Failed), a diff overlay appears showing conflicts between your local changes and the server version.

Use `]c`/`[c` to navigate conflicts, then `gh` (accept server), `gl` (keep local), or `gb` (keep both) to resolve. Save with `:w` to retry.

See [Keymaps](keymaps.md#conflict-resolution-keymaps) for the full keybinding reference.

