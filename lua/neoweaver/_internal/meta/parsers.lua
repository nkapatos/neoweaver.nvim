--- File format parsers for metadata extraction
--- Only JSON is actively used; YAML/TOML retained for potential future use
---@module 'neoweaver._internal.meta.parsers'
local M = {}

--- Detect format from filename
--- @param filename string
--- @return string|nil
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
--- @param path string
--- @return string|nil
local function read_file(path)
  local content = vim.fn.readfile(path)
  if not content then
    return nil
  end
  return table.concat(content, "\n")
end

--- Resolve dotted key path (e.g. "project.name")
--- @param tbl table
--- @param key string
--- @return any|nil
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

--- Parse JSON file
--- @param path string
--- @return table|nil
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

--- Parse YAML file
--- @param path string
--- @return table|nil
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

--- Parse TOML file
--- @param path string
--- @return table|nil
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

--- Parse file by format (auto-detect if not specified)
--- @param path string
--- @param format string|nil
--- @return table|nil
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
--- @param data table
--- @param fields string[]
--- @return table
function M.extract_fields(data, fields)
  local result = {}

  for _, field in ipairs(fields) do
    local raw_value = M.resolve_dotted(data, field)
    if raw_value ~= nil then
      local value = raw_value
      if type(value) == "table" then
        value = value.name or vim.inspect(value):gsub("\n", " ")
      end
      local key = field:gsub("%.", "_"):gsub("[^%w_]", "_")
      result[key] = tostring(value)
    end
  end

  return result
end

--- Parse and extract fields in one call
--- @param path string
--- @param fields string[]
--- @param format string|nil
--- @return table|nil
function M.parse_and_extract(path, fields, format)
  local data = M.parse(path, format)
  if not data then
    return nil
  end

  return M.extract_fields(data, fields)
end

return M
