local Crypto = require('splonebox.crypto')
local uv = require('luv')

local CryptoStream = {}
CryptoStream.__index = CryptoStream

local clpk = Crypto:load_key(".keys/client-long-term.pub")
local clsk = Crypto:load_key(".keys/client-long-term")
local slpk = Crypto:load_key(".keys/server-long-term.pub")
local c = Crypto.new(clpk, clsk, slpk)

function CryptoStream.new(stream)
  return setmetatable({
    _stream = stream
  }, CryptoStream)
end

function CryptoStream:init()
  hello = c:crypto_hello()
  self._stream:write(hello)
end

function CryptoStream:encrypt(data)
  print(data)
  return c:crypto_write(data)
end

function CryptoStream:decrypt(data)
  return c:crypto_read(data)
end

function CryptoStream:read_start(cb, eof_cb)
  self._stream:read_start(function(data)
    if not data then
      print("mofo")
      return eof_cb()
    end
    local type, id_or_cb
    local pos = 1
    local len = #data

    initiate = c:crypto_initiate(data)
    self._stream:write(initiate)

    uv.stop()
    --hello = c:crypto_hello()
    --self._stream:write(hello)
    --while pos <= len do
      --type, id_or_cb, method_or_error, args_or_result, pos =
      --  self._session:receive(data, pos)
    --end
  end)
end

function CryptoStream:read_stop()
  self._stream:read_stop()
end

function CryptoStream:close(signal)
  self._stream:close(signal)
end

return CryptoStream
