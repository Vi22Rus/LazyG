-- LazyG RGB v3 experimental transport encoder.
-- Based on independently implemented wire rules studied in Sertyrew:
-- Protocol.lua, Encode.lua, Crc16.lua. Not installed in the v2 addon.
-- This implements Sertyrew-style protocol version 1 framing, not the
-- experimental LazyG TLV proposal. The 23 cells represent the core layout.
local Encoder = {}

Encoder.CORE_CELLS = 23
Encoder.PLAIN_CELLS = 5
Encoder.VERSION = 1

local floor = math.floor

local function byte(value)
  value = tonumber(value) or 0
  if value ~= value or value < 0 then return 0 end
  if value > 255 then return 255 end
  return floor(value + 0.5)
end

local function xor16(a, b)
  local result, place = 0, 1
  for _ = 1, 16 do
    local left, right = a % 2, b % 2
    if left ~= right then result = result + place end
    a, b, place = floor(a / 2), floor(b / 2), place * 2
  end
  return result
end

function Encoder.Crc16(bytes, first, last)
  local crc = 65535
  for index = first or 1, last or #bytes do
    crc = xor16(crc, bytes[index] * 256)
    for _ = 1, 8 do
      if crc >= 32768 then
        crc = xor16((crc * 2) % 65536, 0x1021)
      else
        crc = (crc * 2) % 65536
      end
    end
  end
  return crc
end

local function cell(r, g, b)
  return { byte(r), byte(g), byte(b) }
end

local function bits(fields)
  local value = 0
  for index, flag in ipairs(fields) do
    if flag == true or (type(flag) == "number" and flag > 0) then
      value = value + 2 ^ (index - 1)
    end
  end
  return value
end

-- Generate the 23 core cells using the same cell indices and principal
-- field positions as Sertyrew. Unsupported values remain zero; callers
-- must use a capability-aware profile before interpreting them as known.
-- Fields omitted by the caller are not claimed to be measured.
function Encoder.BuildCore(data)
  data = data or {}
  local cells = {}
  for i = 1, Encoder.CORE_CELLS do cells[i] = cell(0, 0, 0) end
  cells[1] = cell(255, 0, 255)
  cells[2] = cell(0, 255, 0)
  cells[3] = cell(255, 255, 255)
  cells[4] = cell(0, 0, 0)
  cells[5] = cell(Encoder.VERSION, data.frame or 0,
      (data.encoding or 0) + (data.profileActive and 4 or 0))
  local hash = math.max(0, math.min(65535, floor(tonumber(data.profileHash) or 0)))
  cells[6] = cell(floor(hash / 256), hash % 256,
      byte(data.classId or 0) % 16 +
      (byte(data.talentTree or 0) % 4) * 16 +
      (byte(data.talentGroup or 0) % 2) * 64 +
      (data.untalented and 128 or 0))
  cells[7] = cell(data.addonMajor or 0, data.addonMinor or 0, data.profileIndex or 0)
  cells[8] = cell(bits({ data.inCombat, data.dead, data.mounted, data.onTaxi,
      data.inVehicle, data.keyboardFocus, data.gameMenu, data.modifierDown }),
      bits({ data.moving, data.casting, data.channeling, data.petActive,
      data.stealthed, data.autoRepeat, data.lootOpen, data.petOnTarget }),
      bits({ data.targetExists, data.targetHostile, data.targetDead,
      data.targetCasting, data.targetInterruptible, data.targetInMelee,
      data.targetInSpellRange, data.petAttacking }))
  cells[9] = cell(data.playerHealth or 0, data.targetHealth or 0, data.comboPoints or 0)
  local power = math.max(0, math.min(65535, floor(tonumber(data.power) or 0)))
  local powerMax = math.max(0, math.min(65535, floor(tonumber(data.powerMax) or 0)))
  cells[10] = cell(data.powerType or 0, floor(power / 256), power % 256)
  cells[11] = cell(floor(powerMax / 256), powerMax % 256, data.petHealth or 0)
  cells[12] = cell(data.gcdRemaining or 0, data.gcdDuration or 0, data.latency or 0)
  -- Further core cells (CastRemain .. FocusUnit) accept already packed
  -- RGB triples from a version-specific adapter, to avoid inventing
  -- WoW Forever APIs or silently assuming missing data are false.
  if data.packedCore then
    for i = 13, Encoder.CORE_CELLS do
      local packed = data.packedCore[i]
      if packed then cells[i] = cell(packed[1], packed[2], packed[3]) end
    end
  end
  return cells
end

-- profile-specific extras must be appended in exactly the agreed layout
-- order. The consumer MUST know the expected count and profile hash.
function Encoder.Encode(coreCells, extraCells, mode)
  if type(coreCells) ~= "table" or #coreCells ~= Encoder.CORE_CELLS then
    error("RGB v3 requires exactly 23 core cells")
  end
  extraCells = extraCells or {}
  if #extraCells > 512 then error("RGB v3 profile extension too large") end
  mode = mode or "direct8"
  if mode ~= "direct8" and mode ~= "stepped4" then
    error("unknown RGB encoding")
  end

  local logical = {}
  local function append(one)
    if type(one) ~= "table" or #one ~= 3 then error("invalid RGB cell") end
    for channel = 1, 3 do logical[#logical + 1] = byte(one[channel]) end
  end
  for _, one in ipairs(coreCells) do append(one) end
  for _, one in ipairs(extraCells) do append(one) end
  logical[4 * 3 + 3] = (logical[4 * 3 + 3] - (logical[4 * 3 + 3] % 4)) +
      (mode == "stepped4" and 1 or 0)
  local crc = Encoder.Crc16(logical, 4 * 3 + 1, #logical)
  local checksumCell = #logical / 3
  append(cell(floor(crc / 256), crc % 256, checksumCell % 256))

  if mode == "direct8" then return logical end
  local physical = {}
  local first = Encoder.PLAIN_CELLS * 3
  for i = 1, first do physical[#physical + 1] = logical[i] end
  for i = first + 1, #logical do
    physical[#physical + 1] = floor(logical[i] / 16) * 17
    physical[#physical + 1] = (logical[i] % 16) * 17
  end
  return physical
end

return Encoder
