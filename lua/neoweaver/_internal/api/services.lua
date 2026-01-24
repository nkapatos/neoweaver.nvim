local request_module = require("neoweaver._internal.api.request")
local curl = require("plenary.curl")
local config = require("neoweaver._internal.api.config")

local M = {}

---@class NotesMethods Notes service methods
---@field list fun(req: mind.v3.ListNotesRequest, cb: fun(res: ApiResponse)) List notes
---@field get fun(req: mind.v3.GetNoteRequest, cb: fun(res: ApiResponse)) Get a note
---@field create fun(req: mind.v3.CreateNoteRequest, cb: fun(res: ApiResponse)) Create a note
---@field new fun(req: mind.v3.NewNoteRequest, cb: fun(res: ApiResponse)) Create a new note with auto-generated title
---@field find fun(req: mind.v3.FindNotesRequest, cb: fun(res: ApiResponse)) Find notes by title and filters
---@field update fun(req: mind.v3.ReplaceNoteRequest, etag: string?, cb: fun(res: ApiResponse)) Update a note
---@field delete fun(req: mind.v3.DeleteNoteRequest, cb: fun(res: ApiResponse)) Delete a note
M.notes = {
  list = function(req, cb)
    request_module.request("GET", "/mind.v3.NotesService/ListNotes", {
      body = vim.json.encode(req or {}),
      headers = { ["Content-Type"] = "application/json" },
    }, cb)
  end,

  get = function(req, cb)
    request_module.request("GET", "/mind.v3.NotesService/GetNote", {
      body = vim.json.encode(req),
      headers = { ["Content-Type"] = "application/json" },
    }, cb)
  end,

  create = function(req, cb)
    request_module.request("POST", "/mind.v3.NotesService/CreateNote", {
      body = vim.json.encode(req),
      headers = { ["Content-Type"] = "application/json" },
    }, cb)
  end,

  new = function(req, cb)
    request_module.request("POST", "/mind.v3.NotesService/NewNote", {
      body = vim.json.encode(req or {}),
      headers = { ["Content-Type"] = "application/json" },
    }, cb)
  end,

  find = function(req, cb)
    request_module.request("POST", "/mind.v3.NotesService/FindNotes", {
      body = vim.json.encode(req or {}),
      headers = { ["Content-Type"] = "application/json" },
    }, cb)
  end,

  update = function(req, etag, cb)
    request_module.request("PUT", "/mind.v3.NotesService/ReplaceNote", {
      body = vim.json.encode(req),
      headers = {
        ["Content-Type"] = "application/json",
        ["If-Match"] = etag or "*",
      },
    }, cb)
  end,

  patch = function(req, etag, cb)
    request_module.request("POST", "/mind.v3.NotesService/UpdateNote", {
      body = vim.json.encode(req),
      headers = {
        ["Content-Type"] = "application/json",
        ["If-Match"] = etag,
      },
    }, cb)
  end,

  delete = function(req, cb)
    request_module.request("DELETE", "/mind.v3.NotesService/DeleteNote", {
      body = vim.json.encode(req),
      headers = { ["Content-Type"] = "application/json" },
    }, cb)
  end,
}

---@param collection_id number
---@param query? table
---@param cb fun(res: ApiResponse)
M.list_notes_by_collection = function(collection_id, query, cb)
  local req = vim.tbl_extend("force", query or {}, {
    collectionId = collection_id,
  })
  M.notes.list(req, cb)
end

---@class CollectionsMethods Collections service methods
---@field list fun(req: mind.v3.ListCollectionsRequest, cb: fun(res: ApiResponse)) List collections
---@field get fun(req: mind.v3.GetCollectionRequest, cb: fun(res: ApiResponse)) Get a collection
---@field create fun(req: mind.v3.CreateCollectionRequest, cb: fun(res: ApiResponse)) Create a collection
---@field update fun(req: mind.v3.UpdateCollectionRequest, cb: fun(res: ApiResponse)) Update a collection
---@field delete fun(req: mind.v3.DeleteCollectionRequest, cb: fun(res: ApiResponse)) Delete a collection
M.collections = {
  list = function(req, cb)
    request_module.request("GET", "/mind.v3.CollectionsService/ListCollections", {
      body = vim.json.encode(req or {}),
      headers = { ["Content-Type"] = "application/json" },
    }, cb)
  end,

  get = function(req, cb)
    request_module.request("GET", "/mind.v3.CollectionsService/GetCollection", {
      body = vim.json.encode(req),
      headers = { ["Content-Type"] = "application/json" },
    }, cb)
  end,

  create = function(req, cb)
    request_module.request("POST", "/mind.v3.CollectionsService/CreateCollection", {
      body = vim.json.encode(req),
      headers = { ["Content-Type"] = "application/json" },
    }, cb)
  end,

  update = function(req, cb)
    request_module.request("PUT", "/mind.v3.CollectionsService/UpdateCollection", {
      body = vim.json.encode(req),
      headers = { ["Content-Type"] = "application/json" },
    }, cb)
  end,

  delete = function(req, cb)
    request_module.request("DELETE", "/mind.v3.CollectionsService/DeleteCollection", {
      body = vim.json.encode(req),
      headers = { ["Content-Type"] = "application/json" },
    }, cb)
  end,
}

---@class TagsMethods Tags service methods
---@field list fun(req: mind.v3.ListTagsRequest, cb: fun(res: ApiResponse)) List tags
---@field list_notes_for_tag fun(req: mind.v3.ListNotesForTagRequest, cb: fun(res: ApiResponse)) List notes for a tag
M.tags = {
  list = function(req, cb)
    request_module.request("GET", "/mind.v3.TagsService/ListTags", {
      body = vim.json.encode(req or {}),
      headers = { ["Content-Type"] = "application/json" },
    }, cb)
  end,

  list_notes_for_tag = function(req, cb)
    request_module.request("POST", "/mind.v3.TagsService/ListNotesForTag", {
      body = vim.json.encode(req),
      headers = { ["Content-Type"] = "application/json" },
    }, cb)
  end,
}

M.health = {}

---@param server_name string|nil Server name (nil = current server)
---@param callback fun(result: {ok: boolean, error: string?})
function M.health.ping(server_name, callback)
  local server_url
  if server_name then
    local entry = config.config.servers[server_name]
    if not entry then
      callback({ ok = false, error = "Server not configured: " .. server_name })
      return
    end
    server_url = entry.url
  else
    local ok, url = pcall(config.get_current_server_url)
    if not ok then
      callback({ ok = false, error = tostring(url) })
      return
    end
    server_url = url
  end

  local url = server_url .. "/health"

  curl.get(url, {
    timeout = 2000, -- 2 seconds
    callback = function(res)
      vim.schedule(function()
        if res.status ~= 200 then
          callback({ ok = false, error = "HTTP " .. res.status })
          return
        end

        local ok, body = pcall(vim.json.decode, res.body)
        if not ok then
          callback({ ok = false, error = "Invalid JSON response" })
          return
        end

        if body.status == "healthy" then
          callback({ ok = true })
        else
          callback({ ok = false, error = "Status: " .. (body.status or "unknown") })
        end
      end)
    end,
    on_error = function(err)
      vim.schedule(function()
        callback({ ok = false, error = tostring(err.message or err) })
      end)
    end,
  })
end

return M
