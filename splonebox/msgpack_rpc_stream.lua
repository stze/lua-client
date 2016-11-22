local mpack = require('mpack')

-- temporary hack to be able to manipulate buffer/window/tabpage
local Buffer = {}
Buffer.__index = Buffer
function Buffer.new(id) return setmetatable({id=id}, Buffer) end
local Window = {}
Window.__index = Window
function Window.new(id) return setmetatable({id=id}, Window) end
local Tabpage = {}
Tabpage.__index = Tabpage
function Tabpage.new(id) return setmetatable({id=id}, Tabpage) end

local Response = {}
Response.__index = Response

function Response.new(msgpack_rpc_stream, request_id)
  return setmetatable({
    _msgpack_rpc_stream = msgpack_rpc_stream,
    _request_id = request_id
  }, Response)
end

function Response:send(value, is_error)
  local data = self._msgpack_rpc_stream._session:reply(self._request_id)
  if is_error then
    data = data .. self._msgpack_rpc_stream._pack(value)
    data = data .. self._msgpack_rpc_stream._pack(mpack.NIL)
  else
    data = data .. self._msgpack_rpc_stream._pack(mpack.NIL)
    data = data .. self._msgpack_rpc_stream._pack(value)
  end
  self._msgpack_rpc_stream._stream:write(data)
end

local MsgpackRpcStream = {}
MsgpackRpcStream.__index = MsgpackRpcStream

function MsgpackRpcStream.new(stream, cstream)
  return setmetatable({
    _stream = stream,
    _cstream = cstream,
    _pack = mpack.Packer({
      ext = {
        [Buffer] = function(o) return 0, o.id end,
        [Window] = function(o) return 1, o.id end,
        [Tabpage] = function(o) return 2, o.id end
      }
    }),
    _session = mpack.Session({
      unpack = mpack.Unpacker({
        ext = {
          [0] = function(c, s) return Buffer.new(s) end,
          [1] = function(c, s) return Window.new(s) end,
          [2] = function(c, s) return Tabpage.new(s) end
        }
      })
    }),
  }, MsgpackRpcStream)
end

function MsgpackRpcStream:write(method, args, response_cb)
  local data
  if response_cb then
    assert(type(response_cb) == 'function')
    data = self._session:request(response_cb)
  else
    data = self._session:notify()
  end

  data = data ..  self._pack(method) ..  self._pack(args)
  --print(self._cstream)
  edata = self._cstream:encrypt(data)
  self._stream:write(edata)
end

function MsgpackRpcStream:read_start(request_cb, notification_cb, eof_cb)
  self._stream:read_start(function(data)
    if not data then
      return eof_cb()
    end
    local type, id_or_cb
    local pos = 1
    edata = self._cstream:decrypt(data)
    local len = #edata

    while pos <= len do
      type, id_or_cb, method_or_error, args_or_result, pos =
        self._session:receive(edata, pos)
      if type == 'request' or type == 'notification' then
        if type == 'request' then
          request_cb(method_or_error, args_or_result, Response.new(self,
                                                                   id_or_cb))
        else
          notification_cb(method_or_error, args_or_result)
        end
      elseif type == 'response' then
        if method_or_error == mpack.NIL then
          method_or_error = nil
        else
          args_or_result = nil
        end
        id_or_cb(method_or_error, args_or_result)
      end
    end
  end)
end

function MsgpackRpcStream:read_stop()
  self._stream:read_stop()
end

function MsgpackRpcStream:close(signal)
  self._stream:close(signal)
end

return MsgpackRpcStream
