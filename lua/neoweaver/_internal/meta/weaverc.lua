--- Project-level configuration loader (.weaverc.json, .weaveroot.json)
--- Config keys: quicknotes, api/server overrides
---@module 'neoweaver._internal.meta.weaverc'
local M = {}

local parsers = require("neoweaver._internal.meta.parsers")

---@class WeaverConfig
---@field project? string Project name (overrides auto-detection)
---@field quicknotes? table Quicknotes configuration overrides
---@field api? table API/server configuration overrides
---@field [string] any Additional fields (treated as metadata by extractor)

---@class WeaverConfigCache
---@field data WeaverConfig|nil
---@field mtime number|nil

---@type table<string, WeaverConfigCache>
local cache = {}

--- Find project root
--- @param start_dir? string
--- @return string
function M.find_project_root(start_dir)
  start_dir = start_dir or vim.fn.getcwd()
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

  -- Not found, use cwd as fallback
  return start_dir
end

--- Load and merge config from .weaveroot.json and .weaverc.json
--- @param start_dir? string
--- @return WeaverConfig|nil
function M.load(start_dir)
  start_dir = start_dir or vim.fn.getcwd()
  local root_dir = M.find_project_root(start_dir)

  local result = {}

  local weaveroot_path = root_dir .. "/.weaveroot.json"
  local weaveroot_data = M._load_file(weaveroot_path)
  if weaveroot_data then
    result = vim.tbl_deep_extend("force", result, weaveroot_data)
  end

  -- Collect .weaverc.json from start_dir to root_dir (deeper overrides shallower)
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

  -- Process shallowest first so deeper overrides
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

--- Load and cache a config file
--- @param path string
--- @return table|nil
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

--- Clear cache
--- @param path? string Path to clear (nil = all)
function M.clear_cache(path)
  if path then
    cache[path] = nil
  else
    cache = {}
  end
end

--- Get cache state (for debugging)
--- @return table<string, WeaverConfigCache>
function M._get_cache()
  return cache
end

return M
