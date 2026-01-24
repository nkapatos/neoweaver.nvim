local new_set = MiniTest.new_set
local eq = MiniTest.expect.equality

local T = new_set()

T['api'] = new_set()

T['api']['module loads successfully'] = function()
  local api = require('neoweaver._internal.api')
  eq(type(api), 'table')
end

T['api']['exposes expected services'] = function()
  local api = require('neoweaver._internal.api')
  eq(type(api.notes), 'table')
  eq(type(api.collections), 'table')
  eq(type(api.tags), 'table')
  eq(type(api.health), 'table')
  eq(type(api.events), 'table')
end

T['api']['exposes config functions'] = function()
  local api = require('neoweaver._internal.api')
  eq(type(api.setup), 'function')
  eq(type(api.set_current_server), 'function')
  eq(type(api.list_server_names), 'function')
  eq(type(api.toggle_debug), 'function')
end

return T
