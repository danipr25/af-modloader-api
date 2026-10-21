-- Turns a world's title into a key that is safe in a file name. Pure Lua with no game access, so it is tested
-- without the game (tests/test_world_key.lua).
local world_key = {}

local KEY_MAX = 48
local FNV_OFFSET = 2166136261
local FNV_PRIME = 16777619

-- FNV-1a, 32 bits, over the bytes of the text. Returns 8 lowercase hex digits.
function world_key.fnv1a(text)
  local hash = FNV_OFFSET
  for index = 1, #text do
    hash = ((hash ~ text:byte(index)) * FNV_PRIME) & 0xFFFFFFFF
  end
  return string.format("%08x", hash)
end

-- Bytes outside [A-Za-z0-9_-] become ~XX (uppercase hex), so the key is always plain ASCII (Lua's io.open cannot
-- open paths with other characters). Escaping never makes two titles collide. A key over 48 characters keeps its
-- first 48, then "-" and the hash of the full title, so long titles stay under the Windows path limits and still
-- differ. NTFS ignores case: keys that differ only by case name the same file.
function world_key.make(title)
  local key = title:gsub("[^A-Za-z0-9_%-]", function(char)
    return string.format("~%02X", char:byte())
  end)
  if #key > KEY_MAX then
    key = key:sub(1, KEY_MAX) .. "-" .. world_key.fnv1a(title)
  end
  return key
end

return world_key
