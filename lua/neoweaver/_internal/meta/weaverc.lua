---
--- weaverc.lua - Project-level configuration loader for MindWeaver
---
--- Loads .weaverc.json and .weaveroot.json to provide per-project plugin configuration:
--- - quicknotes: Override quicknotes settings (collection_id, note_type_id, etc.)
--- - api/server: Override server configuration
---
--- Root detection: .weaveroot or .weaveroot.json defines project boundary.
--- If not found, session cwd is used as fallback.
---
--- For metadata extraction, see extractor.lua which collects fields from
--- .weaverc.json, .weaveroot.json, and configured markers.
---
---@module 'neoweaver._internal.meta.weaverc'
local M = {}

local parsers = require("neoweaver._internal.meta.parsers")

---@class WeaverConfig
---@field project? string Project name (overrides auto-detection)
---@field quicknotes? table Quicknotes configuration overrides
---@field api? table API/server configuration overrides
---@field [string] any Additional fields (treated as metadata by extractor)

---@class WeaverConfigCache
---@field data WeaverConfig|nil Parsed config data
---@field mtime number|nil File modification time (seconds since epoch)

-- Cache for loaded config per path
-- Structure: { [path] = WeaverConfigCache }
---@type table<string, WeaverConfigCache>
local cache = {}

--- Find project root by walking up looking for .weaveroot or .weaveroot.json
--- @param start_dir? string Starting directory (defaults to cwd)
--- @return string root_dir Absolute path to project root (or start_dir if not found)
function M.find_project_root(start_dir)
  start_dir = start_dir or vim.fn.getcwd()
  local seen = {}
  local dir = start_dir

  while dir ~= "/" and not seen[dir] do
    seen[dir] = true

    -- Check for .weaveroot (empty file) or .weaveroot.json
    if vim.uv.fs_stat(dir .. "/.weaveroot") then
      return dir
    end
    if vim.uv.fs_stat(dir .. "/.weaveroot.json") then
      return dir
    end

    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then
      break
    end
    dir = parent
  end

  -- No .weaveroot found, use start_dir (cwd) as fallback
  return start_dir
end

--- Load and merge config from .weaveroot.json and .weaverc.json
--- Returns plugin configuration fields from both files (merged).
---
--- @param start_dir? string Starting directory (defaults to cwd)
--- @return WeaverConfig|nil config Merged config, or nil if no files found
function M.load(start_dir)
  start_dir = start_dir or vim.fn.getcwd()
  local root_dir = M.find_project_root(start_dir)

  local result = {}

  -- Load .weaveroot.json first (if exists)
  local weaveroot_path = root_dir .. "/.weaveroot.json"
  local weaveroot_data = M._load_file(weaveroot_path)
  if weaveroot_data then
    result = vim.tbl_deep_extend("force", result, weaveroot_data)
  end

  -- Walk from start_dir to root_dir collecting .weaverc.json files
  -- Deeper files override shallower ones
  local weaverc_files = {}
  local seen = {}
  local dir = start_dir

  while not seen[dir] do
    seen[dir] = true
    local weaverc_path = dir .. "/.weaverc.json"
    if vim.uv.fs_stat(weaverc_path) then
      table.insert(weaverc_files, weaverc_path)
    end
    if dir == root_dir then
      break
    end
    local parent = vim.fn.fnamemodify(dir, ":h")
    if parent == dir then
      break
    end
    dir = parent
  end

  -- Process in reverse order (shallowest first, so deeper overrides)
  for i = #weaverc_files, 1, -1 do
    local weaverc_data = M._load_file(weaverc_files[i])
    if weaverc_data then
      result = vim.tbl_deep_extend("force", result, weaverc_data)
    end
  end

  if vim.tbl_isempty(result) then
    return nil
  end

  return result
end

--- Load and cache a single config file
--- @param path string Absolute path to config file
--- @return table|nil Parsed data or nil
function M._load_file(path)
  local stat = vim.uv.fs_stat(path)
  if not stat then
    -- Clear cache if file was deleted
    if cache[path] then
      cache[path] = nil
    end
    return nil
  end

  -- Check cache validity
  local cached = cache[path]
  if cached and cached.mtime == stat.mtime.sec then
    return vim.deepcopy(cached.data)
  end

  -- Parse file
  local data = parsers.parse_json(path)
  if not data then
    return nil
  end

  -- Update cache
  cache[path] = {
    data = data,
    mtime = stat.mtime.sec,
  }

  return vim.deepcopy(data)
end

--- Clear cache for a specific path or all cached data
--- Useful for testing or manual refresh
---
--- @param path? string Path to clear (if nil, clears all cache)
function M.clear_cache(path)
  if path then
    cache[path] = nil
  else
    cache = {}
  end
end

--- Get current cache state (for debugging/inspection)
--- @return table<string, WeaverConfigCache> Current cache contents
function M._get_cache()
  return cache
end

return M
