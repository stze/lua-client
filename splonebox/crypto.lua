local struct = require("struct")
local nacl = require("nacl")
local posix = require("posix.fcntl")
local bit = require("bit")
local gcrypt = require("luagcrypt")

local Crypto = {}
Crypto.__index = Crypto
counterlow = 0
counterhigh = 0
noncekey = 0
keyloaded = false

local lock = {
  l_type = posix.F_WRLCK;     -- Exclusive lock
  l_whence = posix.SEEK_SET;  -- Relative to beginning of file
  l_start = 0;            -- Start from 1st byte
  l_len = 0;              -- Lock whole file
}

function Crypto.new(clientlongtermpk, clientlongtermsk, serverlongtermpk)
  local self = setmetatable({}, Crypto)
  self.serverlongtermpk = serverlongtermpk
  self.clientlongtermpk = clientlongtermpk
  self.clientlongtermsk = clientlongtermsk
  self.clientshorttermsk = nil
  self.clientshorttermpk = nil
  self.servershorttermpk = nil
  self.nonce = crypto_random_mod(281474976710656)

  if self.nonce % 2 == 0 then
    print(string.format("%.f", self.nonce))
    self.nonce = self.nonce + 1
  end

  self.last_received_nonce = 0

  return self
end

function crypto_random_mod(number)
  result = 0

  if number <= 1 then
    return 0
  end

  local random = nacl.randombytes(32)

  for j=1,32 do
    result = (result * 256 + string.byte(random, j)) % number
  end

  return result
end

function Crypto:load_key(file)
    local f = io.open(file, "rb")
    local content = f:read("*all")
    f:close()
    return content
end

function open_lock(filename)
    local fd = posix.open(filename, bit.bor(posix.O_RDWR, posix.O_CLOEXEC))

    local res = posix.fcntl(fd, posix.F_SETLK, lock)

    if res == -1 then
      error("file locked by another process")
    end

    return fd
end

function open_write(filename)
  local fd = posix.open(filename, bit.bor(posix.O_CREAT, posix.O_WRONLY,
      posix.O_NONBLOCK, posix.O_CLOEXEC), 600)

  return fd
end

function save_sync(filename, data)
  fd = open_write(filename)
  filed = io.open(fd, "wb")
  filed:write(data)
  filed.close()
end

function Crypto:safenonce()
  fdlock = open_lock(".keys/lock")

  if keyloaded == false then
    noncekey = self:load_key(".keys/noncekey")
  end

  if counterlow >= counterhigh then
    noncecounter = self:load_key(".keys/noncecounter")
    counterlow = struct.unpack("<I8", noncecounter)
    counterhigh = counterlow + 1

    data = struct.pack("<I8", counterhigh)
    save_sync(".keys/noncecounter", data)
  end

  data = struct.pack("<I8c8", counterlow, nacl.randombytes(8))
  counterlow = counterlow + 1
  nonce = crypto_block(data, noncekey)

  lock.l_type = posix.F_UNLCK
  posix.fcntl(fdlock, posix.F_SETLK, lock)

  return nonce
end

function crypto_block(data, k)
  local cipher = gcrypt.Cipher(gcrypt.CIPHER_AES256, gcrypt.CIPHER_MODE_CBC)
  cipher:setkey(k)
  cipher:setiv(nacl.randombytes(16))
  local ciphertext = cipher:encrypt(data)
  return ciphertext
end

function Crypto:crypto_verify_length(data)
  if #data < 40 then
    error("Message to short")
  end

  identifier = struct.unpack("<c8", string.sub(data, 1, 8))

  if identifier ~= "rZQTd2nM" then
    error("Received identifier is bad")
  end

  nonce = struct.unpack("<I8", string.sub(data, 9, 16))
  nonceexpanded = struct.pack("<c16I8", "splonebox-server", nonce)

  data = nacl.box_open(string.sub(data, 17, 40), nonceexpanded,
      self.servershorttermpk, self.clientshorttermsk)

  length = struct.unpack("<I8", data)

  return length
end

function Crypto:crypto_nonce_update()
  self.nonce = self.nonce + 2
end

function Crypto:crypto_write(data)
  self:crypto_nonce_update()
  message_nonce = struct.pack("<I8", self.nonce)
  blub = #data + 56
  length = struct.pack("<I8", #data + 56)
  length_nonce = struct.pack("<c16I8", "splonebox-client", self.nonce)
  length_boxed = nacl.box(length, length_nonce, self.servershorttermpk,
      self.clientshorttermsk)
  self:crypto_nonce_update()
  identifier = struct.pack("<c8", "oqQN2kaM")
  data_nonce = struct.pack("<c16I8", "splonebox-client", self.nonce)
  box = nacl.box(data, data_nonce, self.servershorttermpk,
      self.clientshorttermsk)

  return identifier .. message_nonce .. length_boxed .. box
end

function Crypto:crypto_hello()
  self:crypto_nonce_update()
  identifier = struct.pack("<c8", "oqQN2kaH")
  nonce = struct.pack("<c16I8", "splonebox-client", self.nonce)
  local zeros = ("0"):rep(64)
  self.clientshorttermpk, self.clientshorttermsk = nacl.box_keypair()
  box = nacl.box(zeros, nonce, self.serverlongtermpk, self.clientshorttermsk)

  nonce = struct.pack("<I8", self.nonce)
  return identifier .. self.clientshorttermpk .. zeros .. nonce .. box
end

function Crypto:verify_cookiepacket(cookiepacket)
  if #cookiepacket ~= 168 then
    error("Cookie packet has invalid length")
  end

  identifier = struct.unpack("<c8", string.sub(cookiepacket, 1, 8))

  if identifier ~= "rZQTd2nC" then
    error("Received identifier is bad")
  end

  nonce = struct.unpack("<c16", string.sub(cookiepacket, 9, 24))
  nonceexpanded = struct.pack("<c8c16", "splonePK", nonce)

  payload = nacl.box_open(string.sub(cookiepacket, 25, 168),
      nonceexpanded, self.serverlongtermpk, self.clientshorttermsk)

  self.servershorttermpk = struct.unpack("<c32", string.sub(payload, 1, 32))
  cookie = struct.unpack("<c96", string.sub(payload, 33, 128))

  return cookie
end

function Crypto:crypto_initiate(cookiepacket)
  cookie = self:verify_cookiepacket(cookiepacket)

  vouch_payload = self.clientshorttermpk .. self.servershorttermpk
  vouch_nonce = self:safenonce()
  vouch_nonce_expanded = struct.pack("<c8c16", "splonePV", vouch_nonce)

  vouch_box = nacl.box(vouch_payload, vouch_nonce_expanded,
      self.serverlongtermpk, self.clientlongtermsk)

  payload = self.clientlongtermpk .. vouch_nonce .. vouch_box

  self:crypto_nonce_update()

  payload_nonce = struct.pack("c16I8", "splonebox-client", self.nonce)
  payload_box = nacl.box(payload, payload_nonce, self.servershorttermpk,
      self.clientshorttermsk)

  identifier = struct.pack("<c8", "oqQN2kaI")
  nonce = struct.pack("<I8", self.nonce)
  initiatepacket = identifier .. cookie .. nonce .. payload_box

  return initiatepacket
end

function Crypto:crypto_read(data)
  length = self:crypto_verify_length(data)

  nonce = struct.unpack("<I8", string.sub(data, 9, 16))
  self:verify_nonce(nonce)

  nonceexpanded = struct.pack("<c16I8", "splonebox-server", nonce + 2)

  plain = nacl.box_open(string.sub(data, 41, length), nonceexpanded,
      self.servershorttermpk, self.clientshorttermsk)

  self.last_received_nonce = nonce

  return plain
end

function Crypto:verify_nonce(nonce)
  if nonce <= self.last_received_nonce or nonce % 2 == 1 then
    error("Invalid nonce")
  end
end

return Crypto
