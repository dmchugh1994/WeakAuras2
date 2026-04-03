if not WeakAuras.IsLibsOK() then return end

---@type string, Private
local AddonName, Private = ...

-- Filter fingerprinting database for identifying secret auras.
-- Each spec maps filter signatures to known aura data.
--
-- Signatures are built from 4 filter checks via
-- C_UnitAuras.IsAuraFilteredOutByInstanceID:
--   PLAYER|HELPFUL|RAID
--   PLAYER|HELPFUL|RAID_IN_COMBAT
--   PLAYER|HELPFUL|EXTERNAL_DEFENSIVE
--   PLAYER|HELPFUL|RAID_PLAYER_DISPELLABLE
--
-- Credit: Filter fingerprinting technique derived from
-- Harrek's Advanced Raid Frames and DandersFrames.

Private.SecretAuraDatabase = {
  specMap = {
    DRUID_4   = "RestorationDruid",
    SHAMAN_3  = "RestorationShaman",
    PRIEST_1  = "DisciplinePriest",
    PRIEST_2  = "HolyPriest",
    PALADIN_1 = "HolyPaladin",
    EVOKER_2  = "PreservationEvoker",
    EVOKER_3  = "AugmentationEvoker",
    MONK_2    = "MistweaverMonk",
  },

  specs = {
    PreservationEvoker = {
      signatures = {
        ["1:1:1:0"] = { name = "Time Dilation",   spellId = 357170, icon = 4622478 },
        ["1:1:0:0"] = { name = "Rewind",           spellId = 363534, icon = 4622474 },
        ["0:1:0:0"] = { name = "Verdant Embrace",  spellId = 360995, icon = 4622471 },
      },
      disambiguation = {
        -- VerdantEmbrace and Lifebind share signature "0:1:0:0".
        -- If two appear on the same unit within 0.1s, the first is Lifebind.
        -- A single one on the player is also Lifebind.
        ["0:1:0:0"] = {
          spellId = 360995,
          alternatives = {
            { name = "Lifebind", spellId = 373267, icon = 4630453 },
          },
        },
      },
      casts = {
        [357170] = true, -- Time Dilation
        [363534] = true, -- Rewind
        [360995] = true, -- Verdant Embrace / Lifebind
      },
    },

    AugmentationEvoker = {
      signatures = {
        ["0:1:0:0"] = { name = "Sense Power", spellId = 361022, icon = 132160 },
      },
      disambiguation = {
        -- EbonMight and SensePower share "0:1:0:0".
        -- EbonMight is a self-buff (only on caster). SensePower only on others.
        ["0:1:0:0"] = {
          spellId = 361022,
          selfOverride = { name = "Ebon Might", spellId = 395152, icon = 5061347 },
        },
      },
      casts = {},
    },

    RestorationDruid = {
      signatures = {
        ["1:1:1:0"] = { name = "Ironbark", spellId = 102342, icon = 572025 },
      },
      disambiguation = {},
      casts = {
        [102342] = true, -- Ironbark
      },
    },

    DisciplinePriest = {
      signatures = {
        ["1:1:1:0"] = { name = "Pain Suppression",  spellId = 33206, icon = 135936 },
        ["1:0:0:1"] = { name = "Power Infusion",    spellId = 10060, icon = 135939 },
      },
      disambiguation = {},
      casts = {
        [33206] = true, -- Pain Suppression
        [10060] = true, -- Power Infusion
      },
    },

    HolyPriest = {
      signatures = {
        ["1:1:1:0"] = { name = "Guardian Spirit",   spellId = 47788, icon = 237542 },
        ["1:0:0:1"] = { name = "Power Infusion",    spellId = 10060, icon = 135939 },
      },
      disambiguation = {},
      casts = {
        [47788] = true, -- Guardian Spirit
        [10060] = true, -- Power Infusion
      },
    },

    MistweaverMonk = {
      signatures = {
        ["1:1:1:0"] = { name = "Life Cocoon",              spellId = 116849, icon = 627485 },
        ["0:1:0:1"] = { name = "Strength of the Black Ox", spellId = 443113, icon = 615340 },
      },
      disambiguation = {},
      casts = {},
    },

    RestorationShaman = {
      signatures = {},
      disambiguation = {},
      casts = {},
    },

    HolyPaladin = {
      signatures = {
        ["1:1:1:1"] = { name = "Blessing of Protection",  spellId = 1022,   icon = 135964 },
        ["1:1:1:0"] = { name = "Blessing of Sacrifice",   spellId = 6940,   icon = 135966 },
        ["1:0:0:1"] = { name = "Blessing of Freedom",     spellId = 1044,   icon = 135968 },
      },
      disambiguation = {
        -- HolyArmaments and Dawnlight both have "0:1:0:0".
        -- HolyArmaments is cast via 432472; Dawnlight via 431381.
        -- Disambiguate by recent cast if needed, otherwise show first match.
        ["0:1:0:0"] = {
          spellId = 432502,
          alternatives = {
            { name = "Dawnlight", spellId = 431381, icon = 5927633 },
          },
        },
      },
      casts = {
        [1022]   = true, -- Blessing of Protection
        [432472] = true, -- Holy Armaments
        [6940]   = true, -- Blessing of Sacrifice
      },
    },
  },
}

-- Additional "0:1:0:0" entries that need to be in the main signatures table
-- but require disambiguation. We add them here after the table is defined
-- so disambiguation data is already set up.
Private.SecretAuraDatabase.specs.HolyPaladin.signatures["0:1:0:0"] =
  { name = "Holy Armaments", spellId = 432502, icon = 5927636 }
