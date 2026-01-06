--- Conflict resolution diff overlay for save conflicts (412 Precondition Failed)
--- Keys: ]c/[c navigate, gh/gl/gb resolve (server/local/both)
---@class NeoweaverDiff
local M = {}

local ns_id = vim.api.nvim_create_namespace("NeoweaverDiff")
local overlay_ns_id = vim.api.nvim_create_namespace("NeoweaverDiffVirt")

--- Buffer-local state
---@type table<integer, {ref_lines?: string[], hunks?: table[], enabled?: boolean}>
local bufstate = {}

--- Setup highlight groups
local function setup_highlight()
  vim.cmd("highlight default link NeoweaverDiffAdd DiffAdd")
  vim.cmd("highlight default link NeoweaverDiffChange DiffChange")
  vim.cmd("highlight default link NeoweaverDiffDelete DiffDelete")
  vim.cmd("highlight default link NeoweaverDiffText DiffText")
end

--- Clear all extmarks from buffer
---@param bufnr integer
local function clear(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, ns_id, 0, -1)
  vim.api.nvim_buf_clear_namespace(bufnr, overlay_ns_id, 0, -1)
end

--- Compute diff hunks between reference and buffer
---@param ref_lines string[]
---@param buf_lines string[]
---@return table[]
local function compute_hunks(ref_lines, buf_lines)
  assert(type(ref_lines) == "table", "ref_lines must be a table of lines")
  assert(type(buf_lines) == "table", "buf_lines must be a table of lines")

  local ref_str = table.concat(ref_lines, "\n")
  local buf_str = table.concat(buf_lines, "\n")

  ---@diagnostic disable-next-line: param-type-mismatch
  local diff = vim.diff(ref_str, buf_str, {
    result_type = "indices",
    ctxlen = 0,
    interhunkctxlen = 0,
  })

  local hunks = {}
  for _, d in ipairs(diff) do
    local n_ref, n_buf = d[2], d[4]
    local htype = n_ref == 0 and "add" or (n_buf == 0 and "delete" or "change")
    table.insert(hunks, {
      type = htype,
      ref_start = d[1],
      ref_count = n_ref,
      buf_start = d[3],
      buf_count = n_buf,
      resolved = false, -- Track resolution state
    })
  end
  return hunks
end

--- Draw diff overlay (skips resolved hunks)
---@param bufnr integer
local function draw(bufnr)
  clear(bufnr)
  local state = bufstate[bufnr]
  if not state or not state.ref_lines then
    return
  end

  local buf_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local hunks = compute_hunks(state.ref_lines, buf_lines)
  state.hunks = hunks

  for _, h in ipairs(hunks) do
    if h.resolved then
      goto continue
    end

    if h.type == "add" or h.type == "change" then
      -- Highlight local lines
      for l = h.buf_start, h.buf_start + math.max(h.buf_count, 1) - 1 do
        vim.api.nvim_buf_set_extmark(bufnr, ns_id, l - 1, 0, {
          end_row = l,
          hl_group = h.type == "add" and "NeoweaverDiffAdd" or "NeoweaverDiffChange",
          hl_eol = true,
        })
      end

      -- Show server lines as virtual lines if ref has more lines
      local extra = h.ref_count - h.buf_count
      if extra > 0 then
        local virt_lines = {}
        table.insert(virt_lines, {
          { "[SERVER VERSION]", "NeoweaverDiffText" },
        })
        for i = h.ref_start + h.buf_count, h.ref_start + h.ref_count - 1 do
          table.insert(virt_lines, {
            { state.ref_lines[i] or "", h.type == "add" and "NeoweaverDiffAdd" or "NeoweaverDiffChange" },
          })
        end
        table.insert(virt_lines, {
          { "[END SERVER]", "NeoweaverDiffText" },
        })

        local lnum = h.buf_start + h.buf_count - 1
        if lnum < 0 then
          lnum = 0
        end
        vim.api.nvim_buf_set_extmark(bufnr, overlay_ns_id, lnum, 0, {
          virt_lines = virt_lines,
          virt_lines_above = false,
        })
      end

      -- For change hunks, show server lines above
      if h.type == "change" and h.ref_count > 0 then
        local virt_lines = {}
        table.insert(virt_lines, {
          { "═══ SERVER VERSION ═══", "NeoweaverDiffText" },
        })
        for i = h.ref_start, h.ref_start + h.ref_count - 1 do
          table.insert(virt_lines, {
            { state.ref_lines[i] or "", "NeoweaverDiffChange" },
          })
        end
        table.insert(virt_lines, {
          { "═══════════════════════", "NeoweaverDiffText" },
        })

        local lnum = math.max(h.buf_start, 1) - 1
        vim.api.nvim_buf_set_extmark(bufnr, overlay_ns_id, lnum, 0, {
          virt_lines = virt_lines,
          virt_lines_above = true,
        })
      end
    elseif h.type == "delete" then
      local virt_lines = {}
      table.insert(virt_lines, {
        { "[SERVER DELETE]", "NeoweaverDiffText" },
      })
      for i = h.ref_start, h.ref_start + h.ref_count - 1 do
        table.insert(virt_lines, {
          { state.ref_lines[i] or "", "NeoweaverDiffDelete" },
        })
      end
      table.insert(virt_lines, {
        { "[END DELETE]", "NeoweaverDiffText" },
      })

      local lnum = math.max(h.buf_start, 1) - 1
      vim.api.nvim_buf_set_extmark(bufnr, overlay_ns_id, lnum, 0, {
        virt_lines = virt_lines,
        virt_lines_above = true,
      })
    end

    ::continue::
  end
end

---@param bufnr integer
---@param strategy "server"|"local"|"both"
---@return boolean
local function resolve_hunk(bufnr, strategy)
  local state = bufstate[bufnr]
  if not state or not state.hunks then
    return false
  end

  local line = vim.api.nvim_win_get_cursor(0)[1]

  for _, h in ipairs(state.hunks) do
    if h.resolved then
      goto continue
    end

    local from = h.buf_start
    local to = h.buf_start + math.max(h.buf_count, 1) - 1

    if line >= from and line <= to then
      if strategy == "server" then
        -- Accept server version (replace local with server)
        if h.type == "add" or h.type == "change" then
          local new_lines = {}
          for i = h.ref_start, h.ref_start + h.ref_count - 1 do
            table.insert(new_lines, state.ref_lines[i] or "")
          end
          vim.api.nvim_buf_set_lines(bufnr, from - 1, to, false, new_lines)
        elseif h.type == "delete" then
          -- Delete type: insert server lines that were deleted
          local new_lines = {}
          for i = h.ref_start, h.ref_start + h.ref_count - 1 do
            table.insert(new_lines, state.ref_lines[i] or "")
          end
          vim.api.nvim_buf_set_lines(bufnr, from - 1, from - 1, false, new_lines)
        end
      elseif strategy == "local" then -- luacheck: ignore 542
        -- Keep local (no changes needed)
      elseif strategy == "both" then
        -- Keep both with markers - See issue #10
        local both_lines = {}

        -- Add server version first
        table.insert(both_lines, "--- SERVER VERSION ---")
        for i = h.ref_start, h.ref_start + h.ref_count - 1 do
          table.insert(both_lines, state.ref_lines[i] or "")
        end

        table.insert(both_lines, "--- LOCAL VERSION ---")

        table.insert(both_lines, "--- END CONFLICT ---")

        -- Insert before the local content
        vim.api.nvim_buf_set_lines(bufnr, from - 1, from - 1, false, both_lines)
      end

      h.resolved = true
      draw(bufnr)
      return true
    end

    ::continue::
  end

  return false
end

---@param hunks table[]
---@param line integer
---@param dir integer (1=next, -1=prev)
---@return integer|nil
local function find_hunk_idx(hunks, line, dir)
  if not hunks or #hunks == 0 then
    return nil
  end

  if dir == 1 then
    -- Next hunk
    for i, h in ipairs(hunks) do
      if not h.resolved and h.buf_start >= line then
        return i
      end
    end
    -- Wrap to first unresolved
    for i, h in ipairs(hunks) do
      if not h.resolved then
        return i
      end
    end
  else
    -- Previous hunk
    for i = #hunks, 1, -1 do
      local h = hunks[i]
      if not h.resolved then
        local hunk_to = h.buf_start + math.max(h.buf_count, 1) - 1
        if hunk_to < line then
          return i
        end
      end
    end
    -- Wrap to last unresolved
    for i = #hunks, 1, -1 do
      if not hunks[i].resolved then
        return i
      end
    end
  end

  return nil
end

--- Setup highlight groups (call once at startup)
function M.setup()
  setup_highlight()
end

--- Enable diff overlay for buffer
---@param bufnr integer
function M.enable(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  bufstate[bufnr] = bufstate[bufnr] or { enabled = true }
  if bufstate[bufnr].ref_lines then
    draw(bufnr)
  end
end

--- Disable and clear diff overlay
---@param bufnr integer
function M.disable(bufnr)
  bufstate[bufnr] = nil
  clear(bufnr)
end

--- Set reference text (server version) for diffing
---@param bufnr integer
---@param ref_lines string[]
function M.set_ref_text(bufnr, ref_lines)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  if type(ref_lines) == "string" then
    error("set_ref_text: ref_lines must be a table (array of lines), not a string.")
  end
  bufstate[bufnr] = bufstate[bufnr] or {}
  bufstate[bufnr].ref_lines = vim.deepcopy(ref_lines)
  draw(bufnr)
end

--- Move to next unresolved hunk
---@param bufnr integer
function M.goto_next_hunk(bufnr)
  local state = bufstate[bufnr]
  if not state or not state.hunks then
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1]
  local idx = find_hunk_idx(state.hunks, line + 1, 1)

  if idx then
    local h = state.hunks[idx]
    vim.api.nvim_win_set_cursor(0, { h.buf_start, 0 })
  end
end

--- Move to previous unresolved hunk
---@param bufnr integer
function M.goto_prev_hunk(bufnr)
  local state = bufstate[bufnr]
  if not state or not state.hunks then
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1]
  local idx = find_hunk_idx(state.hunks, line, -1)

  if idx then
    local h = state.hunks[idx]
    vim.api.nvim_win_set_cursor(0, { h.buf_start, 0 })
  end
end

--- Accept server version for hunk under cursor
---@param bufnr integer
function M.apply_hunk(bufnr)
  resolve_hunk(bufnr, "server")
end

--- Keep local version for hunk under cursor
---@param bufnr integer
function M.reject_hunk(bufnr)
  resolve_hunk(bufnr, "local")
end

--- Keep both versions for hunk under cursor
---@param bufnr integer
function M.accept_both(bufnr)
  resolve_hunk(bufnr, "both")
end

--- Count unresolved conflicts
---@param bufnr integer
---@return integer
function M.get_conflict_count(bufnr)
  local state = bufstate[bufnr]
  if not state or not state.hunks then
    return 0
  end

  local count = 0
  for _, h in ipairs(state.hunks) do
    if not h.resolved then
      count = count + 1
    end
  end
  return count
end

--- Get conflict summary for statusline
---@param bufnr integer
---@return table|nil { icon, text, hl_group }
function M.get_status_summary(bufnr)
  local count = M.get_conflict_count(bufnr)
  if count == 0 then
    return nil
  end

  return {
    icon = "⚠️",
    text = string.format("%d conflict%s", count, count > 1 and "s" or ""),
    hl_group = "WarningMsg",
  }
end

--- Check for unresolved conflicts
---@param bufnr integer
---@return boolean
function M.has_unresolved_hunks(bufnr)
  return M.get_conflict_count(bufnr) > 0
end

--- Setup buffer-local keymaps for diff navigation/resolution
---@param bufnr integer
function M.map_keys(bufnr)
  vim.keymap.set("n", "]c", function()
    M.goto_next_hunk(bufnr)
  end, { buffer = bufnr, desc = "Next conflict" })
  vim.keymap.set("n", "[c", function()
    M.goto_prev_hunk(bufnr)
  end, { buffer = bufnr, desc = "Previous conflict" })
  vim.keymap.set("n", "gh", function()
    M.apply_hunk(bufnr)
  end, { buffer = bufnr, desc = "Accept server version" })
  vim.keymap.set("n", "gl", function()
    M.reject_hunk(bufnr)
  end, { buffer = bufnr, desc = "Keep local version" })
  vim.keymap.set("n", "gb", function()
    M.accept_both(bufnr)
  end, { buffer = bufnr, desc = "Keep both versions" })
end

return M
