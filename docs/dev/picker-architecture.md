# Picker Architecture

## ViewSource Contract

ViewSource is the interface between domains (collections, tags, future views) and the picker component. Domains implement ViewSource to:

### 1. Provide Data (`load_data`)
- Fetch data from any source (API, filesystem, S3, etc.)
- Build `NuiTree.Node[]` with domain-specific properties attached
- Return nodes via async callback with stats

### 2. Render Nodes (`prepare_node`)
- Convert `NuiTree.Node` to `NuiLine[]` for display
- Use domain properties (`type`, `is_system`, etc.) for rendering decisions
- Control icons, highlights, indentation, suffixes

### 3. Handle Actions (`actions`)
- Receive node with domain properties + `refresh_callback`
- Validate operations (e.g., can't delete system collections)
- Call APIs to perform CRUD operations
- Call `refresh_callback()` to trigger picker reload on success

## Design Decisions

### Why `NuiTree.Node[]` (not generic nodes)
- Domain knows the data shape and what properties exist
- `NuiTree.Node` preserves custom properties (`is_system`, `collection_id`, etc.)
- `prepare_node()` needs these properties for rendering
- Actions need these properties for validation
- Picker stays generic - just passes nodes around

### Why actions receive refresh callback
- Actions are async (API calls)
- Picker doesn't know when action completes
- ViewSource calls `refresh_callback()` after successful operation
- This triggers `picker.load()` which calls `load_data()` again

### Idle timeout
- Hidden pickers start an idle timer (default 5 minutes)
- When timer fires, picker unmounts itself (deletes buffer, unsubscribes SSE)
- Picker self-removes from manager registry via `on_unmount` callback
- Next access to that view creates a fresh picker

### Buffer ownership
- Each picker owns its own buffer (created in `onMount`, deleted in `onUnmount`)
- Hosts (explorer, floating window) swap which buffer is displayed in their window
- This avoids "ghost artifact" bugs where previous tree content bleeds through
