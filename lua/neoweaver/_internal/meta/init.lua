--- Public API for metadata extraction
--- Loads project metadata from .weaveroot.json and auto-detected context
---@module 'neoweaver._internal.meta'
local M = {}

local weaverc = require("neoweaver._internal.meta.weaverc")
local extractor = require("neoweaver._internal.meta.extractor")

---@class MergedMetadata
---@field config? WeaverConfig Plugin config from .weaverc.json/.weaveroot.json
---@field meta? ProjectMetadata Extracted project metadata
---@field [string] any Merged fields from both sources

--- Load complete metadata (config + extracted)
--- @param start_dir? string
--- @return MergedMetadata|nil
function M.load(start_dir)
  local config_data = weaverc.load(start_dir)
  local meta_data = extractor.extract_metadata(start_dir)

  if not config_data and not meta_data then
    return nil
  end

  return {
    config = config_data,
    meta = meta_data,
  }
end

--- Load only plugin configuration
--- @param start_dir? string
--- @return WeaverConfig|nil
function M.load_config(start_dir)
  return weaverc.load(start_dir)
end

--- Load only extracted project metadata
--- @param start_dir? string
--- @return ProjectMetadata|nil
function M.load_metadata(start_dir)
  return extractor.extract_metadata(start_dir)
end

--- Find project root (.weaveroot/.weaveroot.json, fallback to cwd)
--- @param start_dir? string
--- @return string
function M.find_project_root(start_dir)
  return weaverc.find_project_root(start_dir)
end

--- Clear all caches
function M.clear_cache()
  weaverc.clear_cache()
  extractor.clear_cache()
end

--- Get cache state (for debugging)
--- @return table
function M._get_cache()
  return {
    weaverc = weaverc._get_cache(),
    extractor = extractor._get_cache(),
  }
end

return M
