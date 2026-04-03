if not WeakAuras.IsLibsOK() then return end

---@type string, Private
local AddonName, Private = ...

local L = WeakAuras.L
local GetTime = GetTime
local pairs, ipairs, wipe, type = pairs, ipairs, wipe, type
local issecretvalue = issecretvalue or function() return false end
local canaccesstable = canaccesstable or function() return true end

local IsAuraFilteredOutByInstanceID = C_UnitAuras and C_UnitAuras.IsAuraFilteredOutByInstanceID
local GetAuraDataByAuraInstanceID = C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID
local UnitIsUnit = UnitIsUnit
local UnitExists = UnitExists
local UnitClassBase = UnitClassBase
local GetSpecialization = GetSpecialization or C_SpecializationInfo and C_SpecializationInfo.GetSpecialization

local FILTER_RAID = "PLAYER|HELPFUL|RAID"
local FILTER_RIC  = "PLAYER|HELPFUL|RAID_IN_COMBAT"
local FILTER_EXT  = "PLAYER|HELPFUL|EXTERNAL_DEFENSIVE"
local FILTER_DISP = "PLAYER|HELPFUL|RAID_PLAYER_DISPELLABLE"

local CAST_TOLERANCE = 0.15

local SecretAuraEngine = {}
Private.SecretAuraEngine = SecretAuraEngine

local state = {
  spec = nil,
  casts = {},
  identified = {},     -- [unit] = { [auraInstanceID] = { name, spellId, icon } }
  veTimers = {},       -- disambiguation timer state for PreservationEvoker
}

local function GetPlayerSpec()
  if not UnitClassBase or not GetSpecialization then return nil end
  local class = UnitClassBase("player")
  local specNum = GetSpecialization()
  if not class or not specNum then return nil end
  local key = class .. "_" .. specNum
  local db = Private.SecretAuraDatabase
  return db and db.specMap and db.specMap[key]
end

local function MakeSignature(unit, auraInstanceID)
  if not IsAuraFilteredOutByInstanceID then return nil end
  local passesRaid = not IsAuraFilteredOutByInstanceID(unit, auraInstanceID, FILTER_RAID)
  local passesRic  = not IsAuraFilteredOutByInstanceID(unit, auraInstanceID, FILTER_RIC)
  if not passesRaid and not passesRic then return nil end
  local passesExt  = not IsAuraFilteredOutByInstanceID(unit, auraInstanceID, FILTER_EXT)
  local passesDisp = not IsAuraFilteredOutByInstanceID(unit, auraInstanceID, FILTER_DISP)
  return (passesRaid and "1" or "0") .. ":" .. (passesRic and "1" or "0") .. ":"
      .. (passesExt and "1" or "0") .. ":" .. (passesDisp and "1" or "0")
end

local function IsAuraSecret(aura)
  if not aura then return false end
  if issecretvalue(aura.name) then return true end
  if issecretvalue(aura.spellId) then return true end
  return false
end

--- Attempt to identify a secret aura by filter fingerprinting.
--- @param unit string Unit token
--- @param aura table AuraData from C_UnitAuras
--- @return string|nil name Identified aura name, or nil
--- @return number|nil spellId Known spell ID, or nil
--- @return number|nil icon Known icon texture, or nil
function SecretAuraEngine:Identify(unit, aura)
  if not aura or not aura.auraInstanceID then return nil end
  if not IsAuraFilteredOutByInstanceID then return nil end

  if not IsAuraSecret(aura) then return nil end

  local spec = state.spec
  if not spec then return nil end

  local db = Private.SecretAuraDatabase
  if not db or not db.specs or not db.specs[spec] then return nil end
  local specData = db.specs[spec]

  -- Check if we already identified this aura instance
  local unitIdentified = state.identified[unit]
  if unitIdentified and unitIdentified[aura.auraInstanceID] then
    local cached = unitIdentified[aura.auraInstanceID]
    return cached.name, cached.spellId, cached.icon
  end

  local signature = MakeSignature(unit, aura.auraInstanceID)
  if not signature then return nil end

  local match = specData.signatures[signature]
  if not match then return nil end

  local name, spellId, icon = match.name, match.spellId, match.icon

  -- Check disambiguation rules
  local disambig = specData.disambiguation and specData.disambiguation[signature]
  if disambig then
    -- Self-override: aura on self means a different spell
    if disambig.selfOverride and UnitIsUnit(unit, "player") then
      name = disambig.selfOverride.name
      spellId = disambig.selfOverride.spellId
      icon = disambig.selfOverride.icon
    end

    -- Alternative aura detection via VerdantEmbrace/Lifebind pattern:
    -- handled after caching below via ParseDisambiguation
  end

  -- Cache the identification
  if not state.identified[unit] then
    state.identified[unit] = {}
  end
  state.identified[unit][aura.auraInstanceID] = { name = name, spellId = spellId, icon = icon }

  return name, spellId, icon
end

--- Remove cached identification for a removed aura instance.
function SecretAuraEngine:RemoveAura(unit, auraInstanceID)
  if state.identified[unit] then
    state.identified[unit][auraInstanceID] = nil
  end
end

--- Clear all cached state for a unit (e.g., unit token changed).
function SecretAuraEngine:ClearUnit(unit)
  state.identified[unit] = nil
end

--- Record a player spellcast for disambiguation timing.
function SecretAuraEngine:RecordCast(spellId)
  local spec = state.spec
  if not spec then return end
  local db = Private.SecretAuraDatabase
  if not db or not db.specs or not db.specs[spec] then return end
  if db.specs[spec].casts and db.specs[spec].casts[spellId] then
    state.casts[spellId] = GetTime()
  end
end

--- Check if a spell was cast recently (within tolerance).
function SecretAuraEngine:WasCastRecently(spellId, tolerance)
  local castTime = state.casts[spellId]
  if not castTime then return false end
  return (GetTime() - castTime) <= (tolerance or CAST_TOLERANCE)
end

--- Update the current player spec. Called on login and spec change.
function SecretAuraEngine:UpdateSpec()
  local newSpec = GetPlayerSpec()
  if newSpec ~= state.spec then
    state.spec = newSpec
    wipe(state.casts)
    wipe(state.identified)
    wipe(state.veTimers)
  end
end

--- Get the current player spec key.
function SecretAuraEngine:GetSpec()
  return state.spec
end

--- Get the spec database entry for the current spec.
function SecretAuraEngine:GetSpecData()
  local spec = state.spec
  if not spec then return nil end
  local db = Private.SecretAuraDatabase
  return db and db.specs and db.specs[spec]
end

--- Full reset (e.g., on encounter start).
function SecretAuraEngine:Reset()
  wipe(state.casts)
  wipe(state.identified)
  wipe(state.veTimers)
end

--- Clean up units that no longer exist.
function SecretAuraEngine:CleanupUnits()
  for unit in pairs(state.identified) do
    if not UnitExists(unit) then
      state.identified[unit] = nil
    end
  end
end

--- Check if the engine has data for the current spec.
function SecretAuraEngine:IsActive()
  if not IsAuraFilteredOutByInstanceID then return false end
  local spec = state.spec
  if not spec then return false end
  local db = Private.SecretAuraDatabase
  if not db or not db.specs then return false end
  local specData = db.specs[spec]
  return specData ~= nil and specData.signatures ~= nil and next(specData.signatures) ~= nil
end

-- Event frame for spec changes and cast tracking
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")

eventFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "PLAYER_LOGIN" then
    SecretAuraEngine:UpdateSpec()
  elseif event == "PLAYER_SPECIALIZATION_CHANGED" then
    SecretAuraEngine:UpdateSpec()
  elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
    local _, _, spellId = ...
    if spellId then
      SecretAuraEngine:RecordCast(spellId)
    end
  elseif event == "GROUP_ROSTER_UPDATE" then
    SecretAuraEngine:CleanupUnits()
  end
end)
