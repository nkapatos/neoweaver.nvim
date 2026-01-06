--- Project metadata extraction from .weaveroot.json
--- Auto-detected: project, project_root, cwd, commit_hash, git_branch
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
---@field data ProjectMetadata|nil
---@field mtime number|nil
---@field root_dir string|nil

---@type ExtractorCache
local cache = {
  data = nil,
  mtime = nil,
  root_dir = nil,
}

--- Find project root
--- @param start_dir string
--- @return string
local function find_root(start_dir)
  local seen = {}
  local dir = start_dir

  while dir ~= "/" and not seen[dir] do
    seen[dir] = true

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

  -- Not found, use start_dir as fallback
  return start_dir
end

--- Collect .weaveroot.json path if exists
--- @param root_dir string
--- @return string|nil
local function collect_source(root_dir)
  local weaveroot_path = root_dir .. "/.weaveroot.json"
  if vim.uv.fs_stat(weaveroot_path) then
    return weaveroot_path
  end
  return nil
end

--- Extract from .weaveroot.json meta key
--- @param path string
--- @return table|nil
local function extract_from_weaveroot(path)
  local data = parsers.parse_json(path)
  if not data or not data.meta or type(data.meta) ~= "table" then
    return nil
  end

  local result = {}
  for k, v in pairs(data.meta) do
    if type(v) == "table" then
      v = v.name or vim.inspect(v):gsub("\n", " ")
    end
    result[k] = tostring(v)
  end
  return result
end

--- Main extraction with caching
--- @param start_dir? string
--- @return ProjectMetadata|nil
function M.extract_metadata(start_dir)
  start_dir = start_dir or vim.fn.getcwd()

  local root_dir = find_root(start_dir)
  local weaveroot_path = collect_source(root_dir)

  -- Check cache validity
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

  if cache.data and not needs_refresh then
    return vim.deepcopy(cache.data)
  end

  -- Extract fresh metadata
  local meta = {
    project = vim.g.quicknote_project or vim.fn.fnamemodify(root_dir, ":t"),
    cwd = vim.fn.getcwd(),
    commit_hash = vim.fn.systemlist("git rev-parse --short HEAD 2>/dev/null")[1] or nil,
    git_branch = vim.fn.systemlist("git branch --show-current 2>/dev/null")[1] or nil,
    project_root = root_dir,
  }

  -- Merge from .weaveroot.json if present
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

  cache.data = vim.deepcopy(meta)
  return meta
end

--- Clear cache
function M.clear_cache()
  cache.data = nil
  cache.mtime = nil
  cache.root_dir = nil
end

--- Get cache state (for debugging)
--- @return ExtractorCache
function M._get_cache()
  return cache
end

return M
