-- Standalone Lua 5.1+ regression vectors for LazyG's independently written
-- Sertyrew-style encoder; run from repository root.
local codec = dofile("LazyG/AddonTemplate/RgbV3Encoder.lua")

local function check(ok, message)
  if not ok then error("RGB v3 encoder regression failed: " .. message) end
end

local core = codec.BuildCore({
  frame = 7, profileActive = true, profileHash = 0xBEEF,
  classId = 3, talentTree = 1, addonMajor = 1, addonMinor = 1,
  profileIndex = 2, inCombat = true, moving = true,
  targetExists = true, targetHostile = true,
  playerHealth = 77, targetHealth = 54, powerType = 0,
  power = 88, powerMax = 100
})
check(#core == 23, "23 logical core cells")
local direct = codec.Encode(core, {}, "direct8")
check(#direct == 24 * 3, "24 physical cells direct8")
check(direct[13] == 1 and direct[14] == 7 and direct[15] == 4, "header")
check(direct[16] == 0xBE and direct[17] == 0xEF and direct[18] == 0x13, "identity")
check(direct[22] == 1 and direct[23] == 1 and direct[24] == 3, "state flags")
check(direct[25] == 77 and direct[26] == 54, "health")
check(direct[#direct - 2] == 0x8B and direct[#direct - 1] == 0x22
  and direct[#direct] == 23, "base CRC should be 0x8B22")

local extra = codec.Encode(core, { {10, 20, 30}, {255, 0, 15} }, "direct8")
check(#extra == 26 * 3, "26 cells including two profile extras")
check(extra[#extra - 2] == 0xD7 and extra[#extra - 1] == 0x9A
  and extra[#extra] == 25, "profile extension CRC 0xD79A")

local stepped = codec.Encode(core, {}, "stepped4")
check(#stepped == 43 * 3, "43 physical cells stepped4")
check(stepped[15] == 5, "stepped4 header bit")
for index = 16, #stepped do
  check(stepped[index] % 17 == 0, "all encoded 4-bit channels are multiples of 17")
end
check(codec.Crc16({string.byte("123456789", 1, 9)}) == 0x29B1,
  "CRC16-CCITT-FALSE standard test vector")
print("RGB v3 Lua encoder regression: PASS (direct8, stepped4, CRC, profile extensions)")
