---
--- extractor.lua - Project metadata extraction
---
--- Extracts metadata from .weaveroot.json at project root only.
--- .weaverc.json is for plugin settings, not metadata.
---
--- Root detection: .weaveroot or .weaveroot.json defines project boundary.
--- If not found, session cwd is used as fallback.
---
--- Auto-detected fields:
---   - project_root: where .weaveroot.json lives (or cwd fallback)
---   - cwd: current working directory
---   - commit_hash: git short hash
---   - git_branch: current git branch
---   - project: from .weaveroot.json meta, or directory name fallback
---
--- TODO: Future LSP integration fields (see issue #XX):
---   - current_file: buffer path when note was created (for quicknotes from code)
---   - filetype: language of the file being edited
---
---@module 'neoweaver._internal.meta.extractor'
local M = {}

local parsers = require("neoweaver._internal.meta.parsers")

---@class ProjectMetadata
---@field project? string Project name
---@field cwd? string Current working directory
---@field commit_hash? string Git commit hash (short)
---@field git_branch? string Current git branch
---@field project_root? string Detected project root directory
---@field [string] any Additional fields from .weaveroot.json meta

---@class ExtractorCache
---@field data ProjectMetadata|nil Cached metadata
---@field mtime number|nil .weaveroot.json modification time
---@field root_dir string|nil Cached project root

-- Cache for extracted metadata with file modification time tracking
---@type ExtractorCache
local cache = {
  data = nil,
  mtime = nil,
  root_dir = nil,
}

--- Find project root by walking up looking for .weaveroot or .weaveroot.json
--- @param start_dir string Starting directory
--- @return string root_dir Project root (or start_dir if not found)
local function find_root(start_dir)
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

--- Collect metadata sources - only .weaveroot.json at project root
--- @param root_dir string Project root directory
--- @return string|nil weaveroot_path Path to .weaveroot.json or nil if not found
local function collect_source(root_dir)
  local weaveroot_path = root_dir .. "/.weaveroot.json"
  if vim.uv.fs_stat(weaveroot_path) then
    return weaveroot_path
  end
  return nil
end

--- Extract metadata from .weaveroot.json
--- @param path string Path to .weaveroot.json
--- @return table|nil Extracted key-value pairs from `meta` key, or nil
local function extract_from_weaveroot(path)
  local data = parsers.parse_json(path)
  if not data or not data.meta or type(data.meta) ~= "table" then
    return nil
  end

  local result = {}
  for k, v in pairs(data.meta) do
    if type(v) == "table" then
      -- For nested tables, use 'name' field if present, otherwise serialize
      v = v.name or vim.inspect(v):gsub("\n", " ")
    end
    result[k] = tostring(v)
  end
  return result
end

--- Main extraction function with caching support
--- Extracts auto-detected fields + .weaveroot.json meta
---
--- @param start_dir? string Starting directory (defaults to cwd)
--- @return ProjectMetadata|nil Extracted metadata
function M.extract_metadata(start_dir)
  start_dir = start_dir or vim.fn.getcwd()

  -- Find project root
  local root_dir = find_root(start_dir)

  -- Find .weaveroot.json source
  local weaveroot_path = collect_source(root_dir)

  -- Check if cache is valid
  local needs_refresh = false

  if cache.root_dir ~= root_dir then
    needs_refresh = true
    cache.root_dir = root_dir
  end

  if not needs_refresh and weaveroot_path then
    local stat = vim.uv.fs_stat(weaveroot_path)
    if stat then
      local current_mtime = stat.mtime.sec
      if not cache.mtime or current_mtime > cache.mtime then
        needs_refresh = true
      end
    end
  end

  -- Return cached data if still valid
  if cache.data and not needs_refresh then
    return vim.deepcopy(cache.data)
  end

  -- Extract fresh metadata (auto-detected fields)
  local meta = {
    project = vim.g.quicknote_project or vim.fn.fnamemodify(root_dir, ":t"),
    cwd = vim.fn.getcwd(),
    commit_hash = vim.fn.systemlist("git rev-parse --short HEAD 2>/dev/null")[1] or nil,
    git_branch = vim.fn.systemlist("git branch --show-current 2>/dev/null")[1] or nil,
    project_root = root_dir,
  }

  -- Extract from .weaveroot.json if present (meta key overrides auto-detected fields)
  if weaveroot_path then
    local stat = vim.uv.fs_stat(weaveroot_path)
    if stat then
      cache.mtime = stat.mtime.sec
      local extracted = extract_from_weaveroot(weaveroot_path)
      if extracted then
        for k, v in pairs(extracted) do
          meta[k] = v
        end
      end
    end
  end

  -- Cache the result
  cache.data = vim.deepcopy(meta)
  return meta
end

--- Clear cache for all cached metadata
--- Useful for testing or manual refresh
function M.clear_cache()
  cache.data = nil
  cache.mtime = nil
  cache.root_dir = nil
end

--- Get current cache state (for debugging/inspection)
--- @return ExtractorCache Current cache contents
function M._get_cache()
  return cache
end

return M
