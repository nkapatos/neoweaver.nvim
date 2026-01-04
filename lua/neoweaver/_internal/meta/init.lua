---
--- init.lua - Public API for metadata extraction module
---
--- Main entry point for loading project metadata from .weaverc.json,
--- .weaveroot.json, and optionally from configured marker files.
---
--- .weaverc.json and .weaveroot.json are always collected when present.
--- Marker extraction (go.mod, package.json, etc.) is opt-in via:
---   require('neoweaver').setup({ metadata = { extract_from_markers = true } })
---
--- Usage:
---   local meta = require('neoweaver._internal.meta')
---   local data = meta.load() -- Load complete metadata
---
---@module 'neoweaver._internal.meta'
local M = {}

local weaverc = require("neoweaver._internal.meta.weaverc")
local extractor = require("neoweaver._internal.meta.extractor")

---@class MergedMetadata
---@field config? WeaverConfig Plugin config from .weaverc.json/.weaveroot.json
---@field meta? ProjectMetadata Extracted project metadata
---@field [string] any Merged fields from both sources

--- Load complete metadata (plugin config + extracted metadata)
---
--- @param start_dir? string Starting directory (defaults to cwd)
--- @return MergedMetadata|nil Complete metadata or nil if nothing found
function M.load(start_dir)
  -- Load both sources
  local config_data = weaverc.load(start_dir)
  local meta_data = extractor.extract_metadata(start_dir)

  -- Return nil if nothing was found
  if not config_data and not meta_data then
    return nil
  end

  return {
    config = config_data,
    meta = meta_data,
  }
end

--- Load only .weaverc.json/.weaveroot.json plugin configuration
--- @param start_dir? string Starting directory (defaults to cwd)
--- @return WeaverConfig|nil Config data or nil if not found
function M.load_config(start_dir)
  return weaverc.load(start_dir)
end

--- Load only extracted project metadata
--- @param start_dir? string Starting directory (defaults to cwd)
--- @return ProjectMetadata|nil Project metadata or nil if not found
function M.load_metadata(start_dir)
  return extractor.extract_metadata(start_dir)
end

--- Find project root directory
--- Looks for .weaveroot or .weaveroot.json, falls back to cwd
--- @param start_dir? string Starting directory (defaults to cwd)
--- @return string root_dir Absolute path to project root (never nil)
function M.find_project_root(start_dir)
  return weaverc.find_project_root(start_dir)
end

--- Clear all metadata caches
--- Useful for testing or manual refresh
function M.clear_cache()
  weaverc.clear_cache()
  extractor.clear_cache()
end

--- Get current cache state (for debugging/inspection)
--- @return table Cache contents from both weaverc and extractor
function M._get_cache()
  return {
    weaverc = weaverc._get_cache(),
    extractor = extractor._get_cache(),
  }
end

return M
