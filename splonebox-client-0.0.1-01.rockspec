package = 'splonebox-client'
version = '0.0.1-01'
source = {
  url = 'https://github.com/stze/lua-client/archive/' .. version .. '.tar.gz',
  dir = 'lua-client-' .. version,
}
description = {
  summary = 'Lua client to splonebox',
  license = 'Apache'
}
dependencies = {
  'lua >= 5.1',
  'mpack',
  'luv',
  'coxpcall',
  'luatweetnacl',
  'struct',
  'luaposix'
}

local function make_modules()
  return {
    ['splonebox.socket_stream'] = 'splonebox/socket_stream.lua',
    ['splonebox.tcp_stream'] = 'splonebox/tcp_stream.lua',
    ['splonebox.stdio_stream'] = 'splonebox/stdio_stream.lua',
    ['splonebox.child_process_stream'] = 'splonebox/child_process_stream.lua',
    ['splonebox.msgpack_rpc_stream'] = 'splonebox/msgpack_rpc_stream.lua',
    ['splonebox.crypto_stream'] = 'splonebox/crypto_stream.lua',
    ['splonebox.crypto'] = 'splonebox/crypto.lua',
    ['splonebox.session'] = 'splonebox/session.lua',
    ['splonebox.native'] = {
      sources = {'splonebox/native.c'}
    }
  }
end

build = {
  type = 'builtin',
  modules = make_modules(),
}
