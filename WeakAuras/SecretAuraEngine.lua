if not WeakAuras.IsLibsOK() then return end

---@type string, Private
local AddonName, Private = ...

local pairs, ipairs = pairs, ipairs
local CreateFrame = CreateFrame

local AddPrivateAuraAnchor = C_UnitAuras and C_UnitAuras.AddPrivateAuraAnchor
local RemovePrivateAuraAnchor = C_UnitAuras and C_UnitAuras.RemovePrivateAuraAnchor

local SecretAuraEngine = {}
Private.SecretAuraEngine = SecretAuraEngine

local anchors = {} -- [unit] = { anchorIDs = {}, frames = {} }

--- Register private aura anchor frames for a unit.
--- Blizzard renders boss debuff icons into these frames.
--- @param unit string Unit token (e.g., "party1")
--- @param parentFrame Frame Parent frame to attach anchors to
--- @param maxSlots number Maximum anchor slots (default 3)
--- @param iconSize number Icon width/height in pixels (default 20)
--- @param showCountdown boolean Show countdown frame (default true)
--- @param showNumbers boolean Show countdown numbers (default true)
function SecretAuraEngine:RegisterAnchors(unit, parentFrame, maxSlots, iconSize, showCountdown, showNumbers)
  if not AddPrivateAuraAnchor then return end

  self:UnregisterAnchors(unit)

  maxSlots = maxSlots or 3
  iconSize = iconSize or 20
  if showCountdown == nil then showCountdown = true end
  if showNumbers == nil then showNumbers = true end

  local unitAnchors = { anchorIDs = {}, frames = {}, unit = unit }
  anchors[unit] = unitAnchors

  for i = 1, maxSlots do
    local iconFrame = CreateFrame("Frame", nil, parentFrame)
    iconFrame:SetSize(iconSize, iconSize)

    if i == 1 then
      iconFrame:SetPoint("LEFT", parentFrame, "LEFT", 0, 0)
    else
      iconFrame:SetPoint("LEFT", unitAnchors.frames[i - 1], "RIGHT", 2, 0)
    end

    iconFrame:Show()
    unitAnchors.frames[i] = iconFrame

    local success, anchorID = pcall(function()
      return AddPrivateAuraAnchor({
        unitToken = unit,
        auraIndex = i,
        parent = iconFrame,
        showCountdownFrame = showCountdown,
        showCountdownNumbers = showNumbers,
        iconInfo = {
          iconWidth = iconSize,
          iconHeight = iconSize,
          iconAnchor = {
            point = "CENTER",
            relativeTo = iconFrame,
            relativePoint = "CENTER",
            offsetX = 0,
            offsetY = 0,
          },
        },
      })
    end)

    if success and anchorID then
      unitAnchors.anchorIDs[i] = anchorID
    end
  end
end

--- Remove all private aura anchors for a unit.
--- @param unit string Unit token
function SecretAuraEngine:UnregisterAnchors(unit)
  if not RemovePrivateAuraAnchor then return end

  local unitAnchors = anchors[unit]
  if not unitAnchors then return end

  for _, anchorID in ipairs(unitAnchors.anchorIDs) do
    pcall(function() RemovePrivateAuraAnchor(anchorID) end)
  end

  for _, frame in ipairs(unitAnchors.frames) do
    frame:Hide()
    frame:SetParent(nil)
  end

  anchors[unit] = nil
end

--- Remove all anchors for all units.
function SecretAuraEngine:UnregisterAllAnchors()
  for unit in pairs(anchors) do
    self:UnregisterAnchors(unit)
  end
end
