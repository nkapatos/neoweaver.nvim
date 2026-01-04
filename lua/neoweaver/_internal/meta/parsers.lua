---
--- parsers.lua - File format parsers for metadata extraction
---
--- Currently only used for parsing .weaveroot.json (via parse_json).
---
--- Additional parsers (TOML, YAML) and field extraction utilities are retained
--- for potential future use but not actively used by the metadata extractor.
--- These could be useful if we decide to support additional config file formats
--- or re-introduce marker file parsing.
---
---@module 'neoweaver._internal.meta.parsers'
local M = {}

--- Detect file format from filename extension
--- @param filename string The filename to check
--- @return string|nil Format type ("json", "yaml", "toml") or nil if unsupported
function M.detect_format(filename)
  local ext = filename:match("%.([^%.]+)$")

  if ext == "json" or ext == "jsonc" then
    return "json"
  elseif ext == "yaml" or ext == "yml" then
    return "yaml"
  elseif ext == "toml" then
    return "toml"
  end

  return nil
end

--- Read file contents
--- @param path string Absolute path to the file
--- @return string|nil Content as string or nil on error
local function read_file(path)
  local content = vim.fn.readfile(path)
  if not content then
    return nil
  end
  return table.concat(content, "\n")
end

--- Resolve a dotted key path in a table (e.g. "project.name" -> value)
--- @param tbl table The table to search
--- @param key string The key path (possibly dotted like "project.name")
--- @return any|nil The resolved value or nil if not found
function M.resolve_dotted(tbl, key)
  if not key:find(".", 1, true) then
    return tbl[key]
  end

  local value = tbl
  for part in key:gmatch("[^%.]+") do
    if type(value) ~= "table" then
      return nil
    end
    value = value[part]
  end
  return value
end

--- Parse JSON content
--- @param path string Absolute path to the file
--- @return table|nil Parsed data or nil on error
function M.parse_json(path)
  local content = read_file(path)
  if not content then
    return nil
  end

  local ok, decoded = pcall(vim.json.decode, content)
  if not ok then
    vim.notify(
      string.format("[neoweaver] Failed to parse JSON in %s: %s", path, tostring(decoded)),
      vim.log.levels.WARN
    )
    return nil
  end

  if type(decoded) ~= "table" then
    vim.notify(string.format("[neoweaver] JSON in %s is not an object", path), vim.log.levels.WARN)
    return nil
  end

  return decoded
end

--- Parse YAML content
--- @param path string Absolute path to the file
--- @return table|nil Parsed data or nil on error
function M.parse_yaml(path)
  local content = read_file(path)
  if not content then
    return nil
  end

  local ok, yaml_mod = pcall(require, "vim.yaml")
  if not ok then
    vim.notify(string.format("[neoweaver] vim.yaml not available for %s", path), vim.log.levels.WARN)
    return nil
  end

  local ok2, decoded = pcall(yaml_mod.decode, content)
  if not ok2 then
    vim.notify(string.format("[neoweaver] Failed to parse YAML in %s", path), vim.log.levels.WARN)
    return nil
  end

  if type(decoded) ~= "table" then
    vim.notify(string.format("[neoweaver] YAML in %s is not a mapping", path), vim.log.levels.WARN)
    return nil
  end

  return decoded
end

--- Parse TOML content
--- @param path string Absolute path to the file
--- @return table|nil Parsed data or nil on error
function M.parse_toml(path)
  local content = read_file(path)
  if not content then
    return nil
  end

  local ok, toml_mod = pcall(require, "vim.toml")
  if not ok then
    vim.notify(string.format("[neoweaver] vim.toml not available for %s", path), vim.log.levels.WARN)
    return nil
  end

  local ok2, decoded = pcall(toml_mod.decode, content)
  if not ok2 then
    vim.notify(string.format("[neoweaver] Failed to parse TOML in %s", path), vim.log.levels.WARN)
    return nil
  end

  if type(decoded) ~= "table" then
    vim.notify(string.format("[neoweaver] TOML in %s is not a table", path), vim.log.levels.WARN)
    return nil
  end

  return decoded
end

--- Parse a file based on its detected format
--- @param path string Absolute path to the file
--- @param format string|nil Format type ("json", "yaml", "toml") or nil to auto-detect
--- @return table|nil Parsed data or nil on error
function M.parse(path, format)
  if not format then
    local filename = vim.fn.fnamemodify(path, ":t")
    format = M.detect_format(filename)
  end

  if format == "json" then
    return M.parse_json(path)
  elseif format == "yaml" then
    return M.parse_yaml(path)
  elseif format == "toml" then
    return M.parse_toml(path)
  end

  return nil
end

--- Extract specific fields from parsed data
--- @param data table The parsed data
--- @param fields string[] List of field paths to extract (dotted notation supported)
--- @return table Extracted key-value pairs (field paths normalized to underscores)
function M.extract_fields(data, fields)
  local result = {}

  for _, field in ipairs(fields) do
    local raw_value = M.resolve_dotted(data, field)
    if raw_value ~= nil then
      local value = raw_value
      if type(value) == "table" then
        -- Flatten simple tables
        value = value.name or vim.inspect(value):gsub("\n", " ")
      end
      -- Normalize key: "project.name" -> "project_name"
      local key = field:gsub("%.", "_"):gsub("[^%w_]", "_")
      result[key] = tostring(value)
    end
  end

  return result
end

--- Parse a file and extract specific fields
--- @param path string Absolute path to the file
--- @param fields string[] List of field paths to extract
--- @param format string|nil Format type or nil to auto-detect
--- @return table|nil Extracted key-value pairs or nil on error
function M.parse_and_extract(path, fields, format)
  local data = M.parse(path, format)
  if not data then
    return nil
  end

  return M.extract_fields(data, fields)
end

return M
