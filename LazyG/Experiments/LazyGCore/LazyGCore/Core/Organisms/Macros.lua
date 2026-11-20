-- Organism: Macros
-- Per-class macro library (Class / PvE per spec / PvP), a class-agnostic Account list and
-- one-click creation, ported from classic LazyGCore (Core/Macros.lua) and re-written for Forever's spells.
-- Class macros are saved per character (they only work on that class; `general` is the page's
-- "Class" section); the Account list is saved to the General (account) tab for every character.
--
--   S.Macros:Library()            -> { general = {...}, pve = { [specKey] = {...} }, pvp = {...} }
--   S.Macros:AccountList()        -> { entry, ... } (account macros: slots and slash commands only)
--   S.Macros:Create(entry, isGeneral) -> "combat" | "exists" | "full"(, tab) | "created" | "updated"
--                                     (isGeneral = account tab: only for the Account list)
--   S.Macros:Update(entry)        -> "combat" | "missing" | "same" | "updated"
--   S.Macros:Status(entry)        -> "missing" | "exists" | "outdated"
--   S.Macros:Where(entry)         -> "account" | "character" | nil (not created)
--   S.Macros:MoveToCharacter(entry) -> "moved" | "combat" | "missing" | "full"(, tab) | "failed"
--                                     (an older account copy of a class macro -> this character)
--
-- Entry: { name, icon, body, desc }. In-game names are prefixed "S:" (max 16 chars).
-- Bodies use spell names (no ranks) so the highest learned rank is cast.
-- Forever macro limits (Blizzard_MacroUI): 16-letter name, 255-letter body, 120 account +
-- 30 character macros (Constants.MacroConsts).
-- One press only runs /cast lines up to the first spell that starts the GCD; a combo is only
-- "one press" when the earlier spells are off the GCD in Forever's DB2 (StartRecoveryTime 0),
-- otherwise its description says "press again". Checked by review/r11_macros/macrocheck.py.
-- A class template may ship its own `macros` table with the same shape; it then
-- replaces the built-in library for that class.
--
-- Forever notes: no Mangle, Lifebloom, Cyclone, Spell Reflection, Cloak of Shadows,
-- Misdirection, Steady Shot, Seal of Blood or Water Elemental. Curse of Agony is
-- Bane of Agony. Forever-only spells used here: Primal Bite, Wild Growth, Penance,
-- Prayer of Mending, Rage of the Farseer, Holy Strike, Ice Lance. Binding Heal and Lava Burst
-- are gone at launch (Holy Binding and Call of Thunder are passives).
-- Talents (so only in that spec's section): Ice Block (Frost), Inner Focus (Discipline),
-- Nature's Swiftness (Restoration, Shaman and Druid). Judgement does not consume the Seal.
-- No arenas: PvP macros target battlegrounds (focus, mouseover).

local S = LazyGCore
local Secret = S.Atoms.Secret
local Macros = {}
S.Macros = Macros

local QUESTION_MARK = 134400   -- INV_Misc_QuestionMark: lets #showtooltip drive the icon
local MAX_BODY = 255           -- MacroFrameText letters="255" (Blizzard_MacroUI.xml)

local function I(path) return "Interface\\Icons\\" .. path end

-- ============================================================================
-- MACRO DATA (per class token)
-- ============================================================================

local DATA = {
    WARRIOR = {
        general = {
            { name = "Startattack", icon = I("Ability_MeleeDamage"),
              body = "#showtooltip\n/startattack\n/cast Heroic Strike",
              desc = "Ensures auto-attack runs with Heroic Strike" },
            { name = "Stance Swap", icon = I("Ability_Warrior_DefensiveStance"),
              body = "#showtooltip\n/cast [stance:1] Defensive Stance; [stance:2,known:2458] Berserker Stance; Battle Stance",
              desc = "Cycle through all three stances" },
            { name = "Target Near", icon = I("Ability_Warrior_Charge"),
              body = "#showtooltip\n/cleartarget\n/targetenemy [nodead]\n/startattack",
              desc = "Target nearest enemy and start attacking" },
        },
        pve = {
            Arms = {
                { name = "MS Attack", icon = I("Ability_Warrior_SavageBlow"),
                  body = "#showtooltip Mortal Strike\n/startattack\n/cast Mortal Strike",
                  desc = "Mortal Strike with guaranteed auto-attack" },
                { name = "Overpower SD", icon = I("Ability_MeleeDamage"),
                  body = "#showtooltip Overpower\n/cast [stance:1] Overpower; Battle Stance",
                  desc = "Overpower in Battle Stance, else swap to it (press again)" },
            },
            Fury = {
                { name = "BT Attack", icon = I("Spell_Nature_BloodLust"),
                  body = "#showtooltip Bloodthirst\n/startattack\n/cast Bloodthirst",
                  desc = "Bloodthirst with guaranteed auto-attack" },
                { name = "WW+Cleave", icon = I("Ability_Whirlwind"),
                  body = "#showtooltip Whirlwind\n/cast Whirlwind\n/cast !Cleave",
                  desc = "Whirlwind + Cleave queue for AoE" },
            },
            ProtectionWar = {
                { name = "Block+Rev", icon = I("Ability_Defend"),
                  body = "#showtooltip Shield Block\n/cast Shield Block\n/cast Revenge",
                  desc = "Shield Block + Revenge defensive combo" },
                { name = "Shield Slam", icon = I("INV_Shield_05"),
                  body = "#showtooltip Shield Slam\n/startattack\n/cast Shield Slam",
                  desc = "Shield Slam with guaranteed auto-attack" },
            },
        },
        pvp = {
            { name = "Gap Close", icon = I("Ability_Warrior_Charge"),
              -- Forever Charge: "Cannot be used in combat" (Battle); Intercept works in combat (Berserker).
              -- A stance change needs a second press (the stance conditionals read the old stance).
              -- Out of combat it is always Charge (Berserker / Defensive swap to Battle first), in combat Intercept.
              body = "#showtooltip\n/cast [nocombat,stance:1] Charge; [nocombat] Battle Stance; [stance:3] Intercept; [known:2458] Berserker Stance",
              desc = "Charge out of combat, else Intercept; swaps stance first (press again)" },
            { name = "Pummel SD", icon = I("INV_Gauntlets_04"),
              body = "#showtooltip Pummel\n/cast [stance:3] Pummel; Berserker Stance",
              desc = "Pummel in Berserker Stance, else swap to it (press again)" },
            { name = "Disarm SD", icon = I("Ability_Warrior_Disarm"),
              body = "#showtooltip Disarm\n/cast [stance:2] Disarm; Defensive Stance",
              desc = "Disarm in Defensive Stance, else swap to it (press again)" },
            { name = "Hamstring", icon = I("Ability_ShockWave"),
              body = "#showtooltip Hamstring\n/startattack\n/cast Hamstring",
              desc = "Hamstring with auto-attack (slows your target)" },
        },
    },

    ROGUE = {
        general = {
            { name = "Opener", icon = I("Ability_CheapShot"),
              body = "#showtooltip [mod:shift] Garrote; Cheap Shot\n/cast [stealth,mod:shift] Garrote; [stealth] Cheap Shot",
              desc = "Cheap Shot (default) / Garrote (shift)" },
            { name = "PP+Open", icon = I("INV_Misc_Bag_11"),
              body = "#showtooltip\n/cast [stealth] Pick Pocket\n/cast [stealth,mod:shift] Garrote; [stealth] Cheap Shot",
              desc = "Pick Pocket, then Cheap Shot (shift: Garrote)" },
            { name = "Sap Nearest", icon = I("Ability_Sap"),
              body = "#showtooltip Sap\n/cleartarget\n/targetenemy [nodead]\n/cast [stealth] Sap",
              desc = "Target nearest enemy and Sap" },
        },
        pve = {
            Assassination = {
                { name = "Mutilate", icon = I("Ability_Rogue_ShadowStrikes"),
                  body = "#showtooltip Mutilate\n/startattack\n/cast Mutilate",
                  desc = "Mutilate with guaranteed auto-attack" },
                { name = "CB+Evisc", icon = I("Spell_Ice_Lament"),
                  body = "#showtooltip Cold Blood\n/cast Cold Blood\n/cast Eviscerate",
                  desc = "Cold Blood + guaranteed-crit Eviscerate" },
            },
            Combat = {
                { name = "SS Attack", icon = I("Spell_Shadow_RitualOfSacrifice"),
                  body = "#showtooltip Sinister Strike\n/startattack\n/cast Sinister Strike",
                  desc = "Sinister Strike with guaranteed auto-attack" },
                { name = "BF+AR", icon = I("Ability_Warrior_PunishingBlow"),
                  -- both trigger the 1 sec GCD in Forever: one spell per press
                  body = "#showtooltip Blade Flurry\n/cast Blade Flurry\n/cast Adrenaline Rush",
                  desc = "Blade Flurry, press again for Adrenaline Rush" },
            },
            Subtlety = {
                { name = "Hemo", icon = I("Spell_Shadow_LifeDrain"),
                  body = "#showtooltip Hemorrhage\n/startattack\n/cast Hemorrhage",
                  desc = "Hemorrhage with guaranteed auto-attack" },
                { name = "Premed Open", icon = I("Spell_Shadow_Possession"),
                  body = "#showtooltip Premeditation\n/cast [stealth] Premeditation\n/cast [stealth] Cheap Shot",
                  desc = "Premeditation + Cheap Shot opener" },
            },
        },
        pvp = {
            { name = "Blind Focus", icon = I("Spell_Shadow_MindSteal"),
              body = "#showtooltip Blind\n/cast [@focus,harm,nodead] Blind; Blind",
              desc = "Blind on focus / target" },
            { name = "Kick Focus", icon = I("Ability_Kick"),
              body = "#showtooltip Kick\n/cast [@focus,harm,nodead] Kick; Kick",
              desc = "Kick on focus / target" },
            { name = "Vanish Safe", icon = I("Ability_Vanish"),
              body = "#showtooltip Vanish\n/stopattack\n/cast Vanish",
              desc = "Stop auto-attack, then Vanish (so a swing can't break Stealth)" },
            { name = "Sap Focus", icon = I("Ability_Sap"),
              body = "#showtooltip Sap\n/cast [@focus,harm,nodead] Sap; Sap",
              desc = "Sap on focus / target" },
        },
    },

    MAGE = {
        general = {
            { name = "Poly MO", icon = I("Spell_Nature_Polymorph"),
              body = "#showtooltip Polymorph\n/cast [@mouseover,harm,nodead] Polymorph; Polymorph",
              desc = "Polymorph your mouseover or target" },
            { name = "Wand", icon = I("Ability_ShootWand"),
              body = "#showtooltip Shoot\n/cast !Shoot",
              desc = "Start wanding without toggling it off" },
        },
        pve = {
            Arcane = {
                { name = "AP Burst", icon = I("Spell_Nature_Lightning"),
                  body = "#showtooltip Arcane Power\n/use 13\n/cast Arcane Power",
                  desc = "Trinket + Arcane Power burst" },
                -- 16 Oct: Arcane Wrath (3.5s cast) is the biggest cast to make instant
                { name = "PoM Wrath", icon = I("Spell_Nature_EnchantArmor"),
                  body = "#showtooltip Presence of Mind\n/cast Presence of Mind\n/cast Arcane Wrath",
                  desc = "Presence of Mind + instant Arcane Wrath" },
            },
            Fire = {
                { name = "Combust", icon = I("Spell_Fire_SealOfFire"),
                  body = "#showtooltip Combustion\n/use 13\n/cast Combustion",
                  desc = "Trinket + Combustion burst" },
                { name = "Scorch FB", icon = I("Spell_Fire_SoulBurn"),
                  body = "#showtooltip\n/cast [mod:shift] Scorch; Fireball",
                  desc = "Fireball (default) / Scorch (shift)" },
            },
            Frost = {
                { name = "IL Shatter", icon = I("Spell_Frost_FrostBlast"),
                  body = "#showtooltip\n/cast [mod:shift] Ice Lance; Frostbolt",
                  desc = "Frostbolt (default) / Ice Lance (shift)" },
                { name = "Barrier", icon = I("Spell_Ice_Lament"),
                  body = "#showtooltip Ice Barrier\n/cast Ice Barrier",
                  desc = "Ice Barrier on one key" },
                -- Ice Block is a Frost talent in Forever (row 4), not a trainer spell
                { name = "IB Cancel", icon = I("Spell_Frost_Frost"),
                  body = "#showtooltip Ice Block\n/cancelaura Ice Block\n/cast Ice Block",
                  desc = "Ice Block, or cancel it when active" },
            },
        },
        pvp = {
            { name = "CS Focus", icon = I("Spell_Frost_IceShock"),
              body = "#showtooltip Counterspell\n/cast [@focus,harm,nodead] Counterspell; Counterspell",
              desc = "Counterspell on focus / target" },
            { name = "Poly Focus", icon = I("Spell_Nature_Polymorph"),
              body = "#showtooltip Polymorph\n/cast [@focus,harm,nodead] Polymorph; Polymorph",
              desc = "Polymorph on focus / target" },
            { name = "Blink+FN", icon = I("Spell_Arcane_Blink"),
              -- both on the GCD: Frost Nova first, its cooldown lets the next press reach Blink
              body = "#showtooltip Blink\n/cast Frost Nova\n/cast Blink",
              desc = "Frost Nova, press again to Blink away" },
        },
    },

    WARLOCK = {
        general = {
            { name = "Pet+Cast", icon = I("Spell_Shadow_ShadowBolt"),
              body = "#showtooltip\n/petattack\n/cast Shadow Bolt",
              desc = "Send pet + cast Shadow Bolt" },
            { name = "Healthstone", icon = I("INV_Stone_04"),
              -- Healthstone use has no GCD, so a plain "/cast Create Healthstone" after the /use
              -- lines would start a 3 sec create cast (and spend a shard) right after the heal.
              -- Item names: Forever's Create Healthstone tooltips (Minor .. Major Healthstone).
              body = "#showtooltip\n/cast [mod:shift] Create Healthstone\n/stopmacro [mod:shift]\n/use Major Healthstone\n/use Greater Healthstone\n/use Healthstone\n/use Lesser Healthstone\n/use Minor Healthstone",
              desc = "Use your Healthstone (shift: create one)" },
            { name = "Pet Follow", icon = I("Ability_Tracking"),
              body = "#showtooltip\n/petfollow\n/petpassive",
              desc = "Recall pet and set passive" },
        },
        pve = {
            Affliction = {
                { name = "DoTs", icon = I("Spell_Shadow_AbominationExplosion"),
                  body = "#showtooltip Corruption\n/castsequence reset=target/combat Corruption, Bane of Agony",
                  desc = "Corruption then Bane of Agony on each target" },
                { name = "Siphon+Drain", icon = I("Spell_Shadow_Requiem"),
                  body = "#showtooltip\n/cast [mod:shift] Drain Soul; Siphon Life",
                  desc = "Siphon Life (default) / Drain Soul (shift)" },
            },
            Demonology = {
                { name = "Dem Sac", icon = I("Spell_Shadow_PsychicScream"),
                  body = "#showtooltip Demonic Sacrifice\n/cast Demonic Sacrifice",
                  desc = "Sacrifice your demon for its buff" },
                { name = "SB+Pet", icon = I("Spell_Shadow_ShadowBolt"),
                  body = "#showtooltip Shadow Bolt\n/petattack\n/cast Shadow Bolt",
                  desc = "Send pet + Shadow Bolt" },
            },
            Destruction = {
                { name = "SB+Immo", icon = I("Spell_Fire_Immolation"),
                  body = "#showtooltip\n/cast [mod:shift] Immolate; Shadow Bolt",
                  desc = "Shadow Bolt (default) / Immolate (shift)" },
                { name = "SB Burst", icon = I("Spell_Shadow_ShadowBolt"),
                  body = "#showtooltip Shadow Bolt\n/use 13\n/cast Shadow Bolt",
                  desc = "Trinket + Shadow Bolt" },
            },
        },
        pvp = {
            { name = "Fear Focus", icon = I("Spell_Shadow_Possession"),
              body = "#showtooltip Fear\n/cast [@focus,harm,nodead] Fear; Fear",
              desc = "Fear on focus / target" },
            { name = "Coil Stop", icon = I("Spell_Shadow_DeathCoil"),
              body = "#showtooltip Death Coil\n/stopcasting\n/cast Death Coil",
              desc = "Interrupt your cast and Death Coil" },
            { name = "Devour MO", icon = I("Spell_Nature_Purge"),
              body = "#showtooltip Devour Magic\n/cast [@mouseover,help,nodead] Devour Magic; [@player] Devour Magic",
              desc = "Felhunter dispel on mouseover / self" },
            { name = "SpellLock", icon = I("Spell_Shadow_MindRot"),
              body = "#showtooltip Spell Lock\n/cast [@focus,harm,nodead] Spell Lock; Spell Lock",
              desc = "Felhunter interrupt on focus / target" },
        },
    },

    HUNTER = {
        general = {
            { name = "Pet+Mark", icon = I("Ability_Hunter_SniperShot"),
              body = "#showtooltip Hunter's Mark\n/petattack\n/cast Hunter's Mark",
              desc = "Send pet + Hunter's Mark" },
            { name = "Aspect Swap", icon = I("Spell_Nature_RavenForm"),
              body = "#showtooltip\n/cast [nomod] !Aspect of the Hawk; [mod:shift] !Aspect of the Cheetah",
              desc = "Hawk (default) / Cheetah (shift)" },
            { name = "Pet Manage", icon = I("Ability_Hunter_MendPet"),
              body = "#showtooltip\n/petfollow [nomod]\n/petpassive [nomod]\n/cast [mod:shift] Mend Pet",
              desc = "Recall pet and set passive (shift: Mend Pet)" },
        },
        pve = {
            BeastMastery = {
                { name = "BW Burst", icon = I("Ability_Druid_FerociousBite"),
                  body = "#showtooltip Bestial Wrath\n/use 13\n/cast Bestial Wrath",
                  desc = "Trinket + Bestial Wrath" },
                { name = "Intimidate", icon = I("Ability_Devour"),
                  body = "#showtooltip Intimidation\n/petattack\n/cast Intimidation",
                  desc = "Send pet + Intimidation stun" },
            },
            Marksmanship = {
                { name = "Aimed Auto", icon = I("INV_Spear_07"),
                  body = "#showtooltip Aimed Shot\n/cast !Auto Shot\n/cast Aimed Shot",
                  desc = "Aimed Shot; turns Auto Shot on, never off" },
                { name = "RF Burst", icon = I("Ability_Hunter_RunningShot"),
                  body = "#showtooltip Rapid Fire\n/use 13\n/cast Rapid Fire",
                  desc = "Trinket + Rapid Fire" },
            },
            Survival = {
                { name = "Melee", icon = I("Ability_MeleeDamage"),
                  -- Forever Raptor Strike is "Next melee" (off the GCD): it queues even when Mongoose Bite fires
                  body = "#showtooltip Raptor Strike\n/startattack\n/cast Mongoose Bite\n/cast Raptor Strike",
                  desc = "Mongoose Bite when up + Raptor Strike on next swing" },
                { name = "MS+Volley", icon = I("Ability_UpgradeMoonGlaive"),
                  body = "#showtooltip\n/cast [mod:shift] Volley; Multi-Shot",
                  desc = "Multi-Shot (default) / Volley (shift)" },
            },
        },
        pvp = {
            -- Forever traps carry no out-of-combat flag (Charge does), so no Feign Death is needed to
            -- place one; Feign Death is off the GCD, so trap + Feign Death go out on one press.
            { name = "FD+Trap", icon = I("Spell_Frost_ChainsOfIce"),
              body = "#showtooltip Freezing Trap\n/stopattack\n/petpassive\n/cast Freezing Trap\n/cast Feign Death",
              desc = "Stop attacking, set pet passive, then Freezing Trap at your feet + Feign Death in one press" },
            { name = "Scatter", icon = I("Ability_GolemStormBolt"),
              body = "#showtooltip Scatter Shot\n/stopcasting\n/cast Scatter Shot",
              desc = "Interrupt your cast and Scatter Shot (Marksmanship talent)" },
            -- Forever Tranquilizing Shot only removes Frenzy from creatures: Viper Sting is the PvP pick
            { name = "Viper MO", icon = I("Ability_Hunter_AimedShot"),
              body = "#showtooltip Viper Sting\n/cast [@mouseover,harm,nodead] Viper Sting; Viper Sting",
              desc = "Viper Sting (mana drain) on mouseover / target" },
        },
    },

    PRIEST = {
        general = {
            { name = "Heal MO", icon = I("Spell_Holy_FlashHeal"),
              body = "#showtooltip Flash Heal\n/cast [@mouseover,help,nodead] Flash Heal; [@player] Flash Heal",
              desc = "Flash Heal mouseover / self" },
            { name = "Shield MO", icon = I("Spell_Holy_PowerWordShield"),
              body = "#showtooltip Power Word: Shield\n/cast [@mouseover,help,nodead] Power Word: Shield; [@player] Power Word: Shield",
              desc = "Power Word: Shield mouseover / self" },
            { name = "Dispel MO", icon = I("Spell_Holy_DispelMagic"),
              body = "#showtooltip Dispel Magic\n/cast [@mouseover,help,nodead][@mouseover,harm,nodead] Dispel Magic; Dispel Magic",
              desc = "Dispel Magic on mouseover (friend or foe), else target" },
        },
        pve = {
            Discipline = {
                { name = "IF+GHeal", icon = I("Spell_Frost_WindWalkOn"),
                  body = "#showtooltip Greater Heal\n/cast Inner Focus\n/cast [@mouseover,help,nodead] Greater Heal; Greater Heal",
                  desc = "Inner Focus + free Greater Heal on mouseover / target" },
                { name = "Penance MO", icon = I("Spell_Holy_Penance"),
                  body = "#showtooltip Penance\n/cast [@mouseover,help,nodead] Penance; Penance",
                  desc = "Penance on mouseover / target" },
            },
            Holy = {
                -- Inner Focus is a Discipline talent in Forever; Holy Binding (Holy row 4) is a passive
                -- on Flash Heal, which the class-wide "Heal MO" macro already casts
                { name = "PoM MO", icon = I("Spell_Holy_PrayerOfMendingtga"),
                  body = "#showtooltip Prayer of Mending\n/cast [@mouseover,help,nodead] Prayer of Mending; Prayer of Mending",
                  desc = "Prayer of Mending on mouseover / target" },
            },
            Shadow = {
                { name = "SWP+DP", icon = I("Spell_Shadow_ShadowWordPain"),
                  body = "#showtooltip\n/cast [mod:shift] Devouring Plague; Shadow Word: Pain",
                  desc = "Shadow Word: Pain (default) / Devouring Plague (shift)" },
                { name = "SW:D", icon = I("Spell_Shadow_DemonicFortitude"),
                  body = "#showtooltip Shadow Word: Death\n/stopcasting\n/cast Shadow Word: Death",
                  desc = "Interrupt your cast and Shadow Word: Death" },
            },
        },
        pvp = {
            -- was Psychic Scream + Fade: both are on the GCD, and Forever's Fade only lowers threat
            { name = "Stop+Scream", icon = I("Spell_Shadow_PsychicScream"),
              body = "#showtooltip Psychic Scream\n/stopcasting\n/cast Psychic Scream",
              desc = "Interrupt your cast and Psychic Scream" },
            { name = "FW MO", icon = I("Spell_Holy_Excorcism"),
              body = "#showtooltip Fear Ward\n/cast [@mouseover,help,nodead] Fear Ward; [@player] Fear Ward",
              desc = "Fear Ward mouseover / self" },
            { name = "Silence Foc", icon = I("Spell_Shadow_ImpPhaseShift"),
              body = "#showtooltip Silence\n/cast [@focus,harm,nodead] Silence; Silence",
              desc = "Silence on focus / target (Shadow talent)" },
        },
    },

    PALADIN = {
        general = {
            { name = "Bubble HS", icon = I("Spell_Holy_DivineIntervention"),
              -- Divine Shield and Hearthstone are both on the GCD: the second press hearths
              body = "#showtooltip Divine Shield\n/cast Divine Shield\n/use Hearthstone",
              desc = "Divine Shield, press again to Hearthstone" },
            -- Forever Judgement "Does not consume the Seal" and is off the GCD, so re-sealing after it
            -- only wasted a GCD; it now weaves into Holy Strike (trainer spell from level 6).
            { name = "Judge+Strike", icon = I("Spell_Holy_RighteousFury"),
              body = "#showtooltip Holy Strike\n/startattack\n/cast Judgement\n/cast Holy Strike",
              desc = "Judgement + Holy Strike in one press (Judgement is off the GCD)" },
            { name = "DS Cancel", icon = I("Spell_Holy_DivineIntervention"),
              body = "#showtooltip Divine Shield\n/cancelaura Divine Shield\n/cast Divine Shield",
              desc = "Divine Shield, or cancel it when active" },
        },
        pve = {
            HolyPal = {
                { name = "FoL MO", icon = I("Spell_Holy_FlashHeal"),
                  body = "#showtooltip Flash of Light\n/cast [@mouseover,help,nodead] Flash of Light; Flash of Light",
                  desc = "Flash of Light on mouseover / target" },
                { name = "HS MO", icon = I("Spell_Holy_SearingLight"),
                  body = "#showtooltip Holy Shock\n/cast [@mouseover,help,nodead] Holy Shock; [@target,harm] Holy Shock; Holy Shock",
                  desc = "Holy Shock: heal mouseover, else damage or heal target" },
            },
            Protection = {
                { name = "HS+Cons", icon = I("Spell_Holy_BlessingOfProtection"),
                  body = "#showtooltip Holy Shield\n/cast Holy Shield\n/cast Consecration",
                  desc = "Holy Shield when ready, else Consecration" },
                { name = "LoH MO", icon = I("Spell_Holy_LayOnHands"),
                  body = "#showtooltip Lay on Hands\n/cast [@mouseover,help,nodead] Lay on Hands; [@player] Lay on Hands",
                  desc = "Lay on Hands mouseover / self" },
            },
            Retribution = {
                { name = "Seal Twist", icon = I("Ability_Warrior_InnerRage"),
                  body = "#showtooltip\n/cast [mod:shift] Seal of Righteousness; Seal of Command",
                  desc = "Seal of Command (default) / Righteousness (shift)" },
                { name = "HStrike Atk", icon = I("Spell_Holy_HolySmite"),
                  body = "#showtooltip Holy Strike\n/startattack\n/cast Holy Strike",
                  desc = "Holy Strike with guaranteed auto-attack" },
            },
        },
        pvp = {
            { name = "HoJ Focus", icon = I("Spell_Holy_SealOfMight"),
              body = "#showtooltip Hammer of Justice\n/cast [@focus,harm,nodead] Hammer of Justice; Hammer of Justice",
              desc = "Hammer of Justice on focus / target" },
            { name = "Cleanse MO", icon = I("Spell_Holy_Renew"),
              body = "#showtooltip Cleanse\n/cast [@mouseover,help,nodead] Cleanse; [@player] Cleanse",
              desc = "Cleanse mouseover / self" },
            { name = "BoF MO", icon = I("Spell_Holy_SealOfValor"),
              body = "#showtooltip Blessing of Freedom\n/cast [@mouseover,help,nodead] Blessing of Freedom; [@player] Blessing of Freedom",
              desc = "Blessing of Freedom mouseover / self" },
        },
    },

    SHAMAN = {
        general = {
            { name = "ES Focus", icon = I("Spell_Nature_EarthShock"),
              body = "#showtooltip Earth Shock\n/cast [@focus,harm,nodead] Earth Shock; Earth Shock",
              desc = "Earth Shock interrupt on focus / target" },
            { name = "Stop+Shock", icon = I("Spell_Nature_EarthShock"),
              body = "#showtooltip Earth Shock\n/stopcasting\n/cast Earth Shock",
              desc = "Interrupt your cast and Earth Shock" },
            { name = "LS Refresh", icon = I("Spell_Nature_LightningShield"),
              body = "#showtooltip Lightning Shield\n/cast Lightning Shield",
              desc = "Refresh Lightning Shield" },
        },
        pve = {
            Elemental = {
                -- Nature's Swiftness is a Restoration talent in Forever (Lightning Mastery: Elemental 31-pt;
                -- Lava Burst is gone at launch)
                { name = "LB+CL", icon = I("Spell_Nature_ChainLightning"),
                  body = "#showtooltip\n/cast [mod:shift] Chain Lightning; Lightning Bolt",
                  desc = "Lightning Bolt (default) / Chain Lightning (shift)" },
                { name = "FS+ES", icon = I("Spell_Fire_FlameShock"),
                  body = "#showtooltip\n/cast [mod:shift] Earth Shock; Flame Shock",
                  desc = "Flame Shock (default) / Earth Shock (shift)" },
            },
            Enhancement = {
                { name = "SS Attack", icon = I("Ability_Shaman_Stormstrike"),
                  body = "#showtooltip Stormstrike\n/startattack\n/cast Stormstrike",
                  desc = "Stormstrike with guaranteed auto-attack" },
                { name = "Farseer", icon = I("Spell_Nature_ShamanRage"),
                  body = "#showtooltip Rage of the Farseer\n/use 13\n/cast Rage of the Farseer",
                  desc = "Trinket + Rage of the Farseer" },
            },
            RestorationSham = {
                { name = "NS+HW", icon = I("Spell_Nature_RavenForm"),
                  body = "#showtooltip Nature's Swiftness\n/cast Nature's Swiftness\n/cast [@mouseover,help,nodead] Healing Wave; Healing Wave",
                  desc = "Nature's Swiftness + instant Healing Wave on mouseover / target" },
                { name = "CH MO", icon = I("Spell_Nature_HealingWaveGreater"),
                  body = "#showtooltip Chain Heal\n/cast [@mouseover,help,nodead] Chain Heal; Chain Heal",
                  desc = "Chain Heal on mouseover / target" },
            },
        },
        pvp = {
            { name = "Grounding", icon = I("Spell_Nature_GroundingTotem"),
              body = "#showtooltip Grounding Totem\n/stopcasting\n/cast Grounding Totem",
              desc = "Interrupt your cast and drop Grounding Totem" },
            { name = "Purge MO", icon = I("Spell_Nature_Purge"),
              body = "#showtooltip Purge\n/cast [@mouseover,harm,nodead] Purge; Purge",
              desc = "Purge mouseover / target" },
            { name = "FrS+EB", icon = I("Spell_Frost_FrostShock"),
              -- totem GCD (1 sec) blocks Frost Shock; Earthbind's 15 sec cooldown lets press 2 reach it
              body = "#showtooltip Frost Shock\n/cast Earthbind Totem\n/cast Frost Shock",
              desc = "Earthbind Totem, press again for Frost Shock" },
        },
    },

    DRUID = {
        general = {
            { name = "Innerv MO", icon = I("Spell_Nature_Lightning"),
              body = "#showtooltip Innervate\n/cast [@mouseover,help,nodead] Innervate; [@player] Innervate",
              desc = "Innervate mouseover / self" },
            { name = "Decurse MO", icon = I("Spell_Holy_RemoveCurse"),
              body = "#showtooltip Remove Curse\n/cast [@mouseover,help,nodead] Remove Curse; Remove Curse",
              desc = "Remove Curse on mouseover / target" },
            { name = "Drink+Form", icon = I("INV_Drink_18"),
              -- best drink first: drinks share a 1 sec "Item - Drink" category cooldown and no GCD, so
              -- only the first one in your bags (and usable at your level) is drunk
              body = "#showtooltip\n/cancelform [nocombat]\n/use Conjured Crystal Water\n/use Morning Glory Dew\n/use Conjured Sparkling Water\n/use Moonberry Juice\n/use Conjured Mineral Water\n/use Sweet Nectar\n/use Melon Juice\n/use Ice Cold Milk",
              desc = "Leave form, then drink" },
        },
        pve = {
            Balance = {
                -- Nature's Swiftness is a Restoration talent in Forever
                { name = "SF Burst", icon = I("Spell_Arcane_StarFire"),
                  body = "#showtooltip Starfire\n/use 13\n/cast Starfire",
                  desc = "Trinket + Starfire" },
                { name = "MF+Wrath", icon = I("Spell_Nature_StarFall"),
                  body = "#showtooltip\n/cast [mod:shift] Moonfire; Wrath",
                  desc = "Wrath (default) / Moonfire (shift)" },
            },
            Feral = {
                { name = "PB+Maul", icon = I("Ability_Druid_Maul"),
                  body = "#showtooltip Primal Bite\n/startattack\n/cast !Maul\n/cast Primal Bite",
                  desc = "Queue Maul + Primal Bite (Bear)" },
                { name = "Shred Ravage", icon = I("Spell_Shadow_VampiricAura"),
                  body = "#showtooltip\n/cast [stealth] Ravage; Shred\n/startattack [nostealth]",
                  desc = "Ravage from Prowl, Shred otherwise (Cat)" },
            },
            Restoration = {
                { name = "NS+HT", icon = I("Spell_Nature_HealingTouch"),
                  body = "#showtooltip Nature's Swiftness\n/cast Nature's Swiftness\n/cast [@mouseover,help,nodead] Healing Touch; Healing Touch",
                  desc = "Nature's Swiftness + instant Healing Touch on mouseover / target" },
                { name = "WG MO", icon = I("Ability_Druid_Flourish"),
                  body = "#showtooltip Wild Growth\n/cast [@mouseover,help,nodead] Wild Growth; Wild Growth",
                  desc = "Wild Growth on mouseover / target" },
                { name = "Rejuv MO", icon = I("Spell_Nature_Rejuvenation"),
                  body = "#showtooltip Rejuvenation\n/cast [@mouseover,help,nodead] Rejuvenation; Rejuvenation",
                  desc = "Rejuvenation on mouseover / target" },
            },
        },
        pvp = {
            { name = "Roots Focus", icon = I("Spell_Nature_StrangleVines"),
              body = "#showtooltip Entangling Roots\n/cast [@focus,harm,nodead] Entangling Roots; Entangling Roots",
              desc = "Entangling Roots on focus / target" },
            { name = "Bash", icon = I("Ability_Druid_Bash"),
              -- form 1 = Bear / Dire Bear (Dire Bear Form 9634 supersedes Bear Form at 40, same slot)
              body = "#showtooltip Bash\n/cast [form:1] Bash; [known:9634] Dire Bear Form; Bear Form",
              desc = "Bash in Bear Form, else shift to Bear (press again)" },
            { name = "Travel", icon = I("Ability_Druid_TravelForm"),
              body = "#showtooltip\n/cast [swimming] Aquatic Form; [indoors] Cat Form; Travel Form",
              desc = "Aquatic / Cat / Travel form by location" },
            { name = "Abolish MO", icon = I("Spell_Nature_NullifyPoison_02"),
              body = "#showtooltip Abolish Poison\n/cast [@mouseover,help,nodead] Abolish Poison; [@player] Abolish Poison",
              desc = "Abolish Poison mouseover / self" },
        },
    },
}
Macros.DATA = DATA

-- Class-agnostic macros, saved as account (General tab) macros so every character has them.
-- No spell or item names: equipment slots and slash commands are the same in every client language.
-- (Class macros above are saved per character: they only work on that class.)
local ACCOUNT = {
    { name = "Trinket 1", icon = I("INV_Jewelry_Talisman_07"),
      body = "#showtooltip 13\n/use 13",
      desc = "Use your top trinket (slot 13)" },
    { name = "Trinket 2", icon = I("INV_Jewelry_Talisman_08"),
      body = "#showtooltip 14\n/use 14",
      desc = "Use your bottom trinket (slot 14)" },
    { name = "Set Focus", icon = I("Ability_Hunter_MarkedForDeath"),
      body = "/focus [@mouseover,exists][]",
      desc = "Focus your mouseover, else your target" },
    { name = "Clear Focus", icon = I("Spell_ChargeNegative"),
      body = "/clearfocus",
      desc = "Clear your focus" },
    { name = "Assist Focus", icon = I("Ability_Hunter_SniperShot"),
      body = "/assist focus",
      desc = "Target what your focus is targeting" },
    { name = "Skull Target", icon = I("INV_Misc_Bone_HumanSkull_01"),
      body = "/tm 8",
      desc = "Put a Skull on your target (press again to remove it)" },
    { name = "Ready Check", icon = I("Spell_ChargePositive"),
      body = "/readycheck",
      desc = "Start a ready check (group leader or raid assistant)" },
    { name = "LazyGCore Toggle", icon = I("Spell_Nature_TimeStop"),
      body = "/lazygcore toggle",
      desc = "Show or hide the LazyGCore rotation display" },
    { name = "Reload UI", icon = I("INV_Misc_Gear_01"),
      body = "/reload",
      desc = "Reload the user interface" },
}
Macros.ACCOUNT = ACCOUNT

-- Spec order + display names used when no class template is registered
Macros.SPECS = {
    WARRIOR = { { "Arms", "Arms" }, { "Fury", "Fury" }, { "ProtectionWar", "Protection" } },
    ROGUE = { { "Assassination", "Assassination" }, { "Combat", "Combat" }, { "Subtlety", "Subtlety" } },
    MAGE = { { "Arcane", "Arcane" }, { "Fire", "Fire" }, { "Frost", "Frost" } },
    WARLOCK = { { "Affliction", "Affliction" }, { "Demonology", "Demonology" }, { "Destruction", "Destruction" } },
    HUNTER = { { "BeastMastery", "Beast Mastery" }, { "Marksmanship", "Marksmanship" }, { "Survival", "Survival" } },
    PRIEST = { { "Discipline", "Discipline" }, { "Holy", "Holy" }, { "Shadow", "Shadow" } },
    PALADIN = { { "HolyPal", "Holy" }, { "Protection", "Protection" }, { "Retribution", "Retribution" } },
    SHAMAN = { { "Elemental", "Elemental" }, { "Enhancement", "Enhancement" }, { "RestorationSham", "Restoration" } },
    DRUID = { { "Balance", "Balance" }, { "Feral", "Feral Combat" }, { "Restoration", "Restoration" } },
}

-- ============================================================================
-- QUERIES
-- ============================================================================

--- Macro library for the player's class (template `macros` table wins).
function Macros:Library(classToken)
    classToken = classToken or S.classToken
    if classToken == S.classToken and S.Registry then
        local cls = S.Registry.Class()
        if cls and type(cls.macros) == "table" then return cls.macros end
    end
    return DATA[classToken]
end

--- Class-agnostic account macros (the "Account (all characters)" section).
function Macros:AccountList() return ACCOUNT end

--- Ordered PvE sections: { { key, title, list }, ... }
function Macros:SpecSections(classToken)
    classToken = classToken or S.classToken
    local lib = self:Library(classToken)
    local out = {}
    if not (lib and lib.pve) then return out end
    local seen = {}
    local specs = (classToken == S.classToken and S.Registry) and S.Registry.Specs() or {}
    for _, spec in ipairs(specs) do
        local list = lib.pve[spec.key]
        if list and #list > 0 then
            out[#out + 1] = { spec.key, spec.name or spec.key, list }
            seen[spec.key] = true
        end
    end
    for _, s in ipairs(self.SPECS[classToken] or {}) do
        local list = lib.pve[s[1]]
        if not seen[s[1]] and list and #list > 0 then
            out[#out + 1] = { s[1], s[2], list }
            seen[s[1]] = true
        end
    end
    return out
end

function Macros:GameName(entry) return "S:" .. tostring(entry.name) end

-- ============================================================================
-- LOCALIZED BODIES
-- ============================================================================
-- Library bodies are written with English spell names, but a macro only works with the
-- client's own spell names (a German client does not know "/cast Polymorph"). So every
-- spell name in #showtooltip / #show / /cast / /use / /castsequence / /castrandom /
-- /cancelaura arguments is rewritten to the client's name (C_Spell.GetSpellName of a
-- known spell ID: the class template's spell defs, then MACRO_SPELL_IDS below). Names
-- without a known ID, item slots (/use 13) and conditionals stay as written.

-- Spells used in macro bodies that are not (or not always) in a class template.
local MACRO_SPELL_IDS = {
    ["Shoot"] = 5019, ["Auto Shot"] = 75, ["Attack"] = 6603,
    ["Cleave"] = 845, ["Heroic Strike"] = 78, ["Battle Stance"] = 2457, ["Defensive Stance"] = 71,
    ["Berserker Stance"] = 2458, ["Charge"] = 100, ["Intercept"] = 20252, ["Pummel"] = 6552,
    ["Disarm"] = 676, ["Hamstring"] = 1715, ["Overpower"] = 7384, ["Revenge"] = 6572,
    ["Shield Block"] = 2565, ["Shield Bash"] = 72, ["Whirlwind"] = 1680, ["Mortal Strike"] = 12294,
    ["Bloodthirst"] = 23881, ["Shield Slam"] = 23922, ["Bloodrage"] = 2687, ["Berserker Rage"] = 18499,
    ["Garrote"] = 703, ["Cheap Shot"] = 1833, ["Pick Pocket"] = 921, ["Sap"] = 6770, ["Mutilate"] = 1310707,
    ["Cold Blood"] = 14177, ["Eviscerate"] = 2098, ["Sinister Strike"] = 1752, ["Blade Flurry"] = 13877,
    ["Adrenaline Rush"] = 13750, ["Hemorrhage"] = 16511, ["Premeditation"] = 14183, ["Blind"] = 2094,
    ["Kick"] = 1766, ["Vanish"] = 1856, ["Stealth"] = 1784, ["Ambush"] = 8676, ["Backstab"] = 53,
    ["Ice Block"] = 11958, ["Polymorph"] = 118, ["Arcane Power"] = 12042, ["Presence of Mind"] = 12043, ["Arcane Wrath"] = 1326079,
    ["Pyroblast"] = 11366, ["Scorch"] = 2948, ["Fireball"] = 133, ["Combustion"] = 11129,
    ["Ice Lance"] = 1312002, ["Frostbolt"] = 116, ["Ice Barrier"] = 11426, ["Counterspell"] = 2139,
    ["Blink"] = 1953, ["Frost Nova"] = 122, ["Cold Snap"] = 12472, ["Evocation"] = 12051,
    ["Fire Blast"] = 2136, ["Arcane Missiles"] = 5143, ["Arcane Explosion"] = 1449,
    ["Power Word: Shield"] = 17, ["Renew"] = 139, ["Flash Heal"] = 2061, ["Psychic Scream"] = 8122,
    ["Fade"] = 586, ["Shadow Word: Pain"] = 589, ["Devouring Plague"] = 2944, ["Shadow Word: Death"] = 1309595,
    ["Silence"] = 15487, ["Mind Blast"] = 8092, ["Inner Focus"] = 14751, ["Greater Heal"] = 2060,
    ["Dispel Magic"] = 527, ["Mind Flay"] = 15407, ["Penance"] = 402174, ["Prayer of Mending"] = 401859,
    ["Holy Fire"] = 14914, ["Smite"] = 585, ["Vampiric Embrace"] = 15286, ["Shadowform"] = 15473,
    ["Lesser Heal"] = 2050, ["Heal"] = 2054, ["Desperate Prayer"] = 13908,
    ["Shadow Bolt"] = 686, ["Immolate"] = 348, ["Corruption"] = 172, ["Fear"] = 5782,
    ["Death Coil"] = 6789, ["Howl of Terror"] = 5484, ["Drain Soul"] = 1120, ["Drain Life"] = 689,
    ["Life Tap"] = 1454, ["Spell Lock"] = 19244, ["Devour Magic"] = 19505, ["Shadowburn"] = 17877, ["Conflagrate"] = 17962,
    ["Siphon Life"] = 18265, ["Searing Pain"] = 5676, ["Soul Fire"] = 6353, ["Banish"] = 710,
    ["Health Funnel"] = 755, ["Shadow Ward"] = 6229, ["Amplify Curse"] = 18288, ["Curse of Exhaustion"] = 18223,
    ["Hunter's Mark"] = 1130, ["Arcane Shot"] = 3044, ["Serpent Sting"] = 1978, ["Viper Sting"] = 3034,
    ["Scatter Shot"] = 19503, ["Rapid Fire"] = 3045, ["Aimed Shot"] = 19434, ["Multi-Shot"] = 2643,
    ["Concussive Shot"] = 5116, ["Freezing Trap"] = 1499, ["Feign Death"] = 5384, ["Disengage"] = 781,
    ["Raptor Strike"] = 2973, ["Mongoose Bite"] = 1495, ["Wing Clip"] = 2974, ["Bestial Wrath"] = 19574,
    ["Intimidation"] = 19577, ["Mend Pet"] = 136, ["Call Pet"] = 883, ["Revive Pet"] = 982,
    ["Dismiss Pet"] = 2641, ["Wyvern Sting"] = 19386, ["Counterattack"] = 19306, ["Tranquilizing Shot"] = 19801,
    ["Aspect of the Hawk"] = 13165, ["Aspect of the Monkey"] = 13163, ["Aspect of the Cheetah"] = 5118,
    ["Earth Shock"] = 8042, ["Flame Shock"] = 8050, ["Frost Shock"] = 8056, ["Lightning Bolt"] = 403,
    ["Chain Lightning"] = 421, ["Stormstrike"] = 17364, ["Purge"] = 370, ["Healing Wave"] = 331,
    ["Lesser Healing Wave"] = 8004, ["Chain Heal"] = 1064, ["Nature's Swiftness"] = 16188,
    ["Ghost Wolf"] = 2645, ["Grounding Totem"] = 8177, ["Tremor Totem"] = 8143,
    ["Riptide"] = 408521, ["Lightning Shield"] = 324,
    ["Rejuvenation"] = 774, ["Regrowth"] = 8936, ["Healing Touch"] = 5185, ["Swiftmend"] = 18562,
    ["Wild Growth"] = 408120, ["Entangling Roots"] = 339, ["Hibernate"] = 2637,
    ["Moonfire"] = 8921, ["Wrath"] = 5176, ["Starfire"] = 2912, ["Insect Swarm"] = 5570,
    ["Faerie Fire"] = 770, ["Faerie Fire (Feral)"] = 16857, ["Cat Form"] = 768, ["Bear Form"] = 5487,
    ["Dire Bear Form"] = 9634, ["Travel Form"] = 783, ["Aquatic Form"] = 1066, ["Moonkin Form"] = 24858,
    ["Prowl"] = 5215, ["Shred"] = 5221, ["Ravage"] = 6785, ["Pounce"] = 9005, ["Claw"] = 1082,
    ["Rake"] = 1822, ["Rip"] = 1079, ["Ferocious Bite"] = 22568, ["Maul"] = 6807, ["Swipe"] = 779,
    ["Bash"] = 5211, ["Feral Charge"] = 1238122, ["Dash"] = 1850, ["Barkskin"] = 22812, ["Innervate"] = 29166,
    ["Tiger's Fury"] = 5217, ["Remove Curse"] = 2782, ["Abolish Poison"] = 2893, ["Nature's Grasp"] = 16689,
    ["Holy Light"] = 635, ["Flash of Light"] = 19750, ["Holy Shock"] = 20473, ["Divine Favor"] = 20216,
    ["Divine Shield"] = 642, ["Blessing of Protection"] = 1022, ["Blessing of Freedom"] = 1044,
    ["Hammer of Justice"] = 853, ["Judgement"] = 20271, ["Seal of Righteousness"] = 20154,
    ["Seal of Command"] = 20375, ["Seal of the Crusader"] = 21082, ["Seal of Justice"] = 20164,
    ["Seal of Light"] = 20165, ["Seal of Wisdom"] = 20166, ["Consecration"] = 26573, ["Holy Shield"] = 20925,
    ["Exorcism"] = 879, ["Hammer of Wrath"] = 24275, ["Cleanse"] = 4987, ["Purify"] = 1152,
    ["Lay on Hands"] = 633, ["Repentance"] = 20066, ["Righteous Fury"] = 25780,
}

-- Items used in macro bodies (/use <name>): the client's item name, else "item:<id>".
local MACRO_ITEM_IDS = {
    ["Hearthstone"] = 6948, ["Major Healthstone"] = 9421, ["Greater Healthstone"] = 5510,
    ["Healthstone"] = 5509, ["Lesser Healthstone"] = 5511, ["Minor Healthstone"] = 5512,
    ["Conjured Crystal Water"] = 8079, ["Major Mana Potion"] = 13444, ["Major Healing Potion"] = 13446,
    ["Conjured Sparkling Water"] = 8078, ["Conjured Mineral Water"] = 8077, ["Morning Glory Dew"] = 8766,
    ["Moonberry Juice"] = 1645, ["Sweet Nectar"] = 1708, ["Melon Juice"] = 1205, ["Ice Cold Milk"] = 1179,
}
local itemByName = {}
for n, id in pairs(MACRO_ITEM_IDS) do itemByName[n:lower()] = id end

local idByName       -- lower English name -> spell ID (template defs win)
local function KnownIds()
    if idByName then return idByName end
    local t = {}
    for n, id in pairs(MACRO_SPELL_IDS) do t[n:lower()] = id end
    local cls = S.Registry and S.Registry.Class()
    for _, def in pairs(cls and cls.spells or {}) do
        if type(def) == "table" then
            local n = def.name or def[1]
            local ids = def.ids or (def.id and { def.id })
            if type(n) == "string" and type(ids) == "table" and ids[1] then t[n:lower()] = ids[1] end
        end
    end
    if cls then idByName = t end
    return t
end

local uncachedItem = false   -- set while Body() builds: an item name was not cached yet

--- Client name for an English spell name used in a macro (unchanged when unknown).
local function ClientName(name)
    local key = name:lower()
    local id = KnownIds()[key]
    local n = id and S.Atoms.Spells.NameById(id)
    if type(n) == "string" and n ~= "" then return n end
    local item = itemByName[key]
    -- English clients keep the library text; others get the client's item name ("item:<id>"
    -- while the item is not cached - a valid macro argument too)
    if item and not (GetLocale and tostring(GetLocale()):sub(1, 2) == "en") then
        local n = S.Atoms.Items.Name(item)
        if not n or n:find("^item:") then uncachedItem = true end
        return n or name
    end
    return name
end

local function MapItem(item)
    local pre, name, post = item:match("^(%s*!?)(.-)(%s*)$")
    if not name or name == "" or name:match("^%d+$") then return item end
    return pre .. ClientName(name) .. post
end

local function LocalizeSegment(seg, isSequence)
    local pos = 1
    while true do
        local s, e = seg:find("^%s*%b[]", pos)
        if not s then break end
        pos = e + 1
    end
    if isSequence then
        local s, e = seg:find("^%s*reset=%S+", pos)
        if s then pos = e + 1 end
    end
    local head, rest = seg:sub(1, pos - 1), seg:sub(pos)
    return head .. rest:gsub("[^,]+", MapItem)
end

local SPELL_CMDS = { ["#showtooltip"] = true, ["#show"] = true, ["/cast"] = true, ["/use"] = true,
    ["/castsequence"] = true, ["/castrandom"] = true, ["/cancelaura"] = true }

local bodyCache = {}
--- Macro body with every spell name in the client's language.
function Macros:Body(entry)
    local body = entry and entry.body
    if type(body) ~= "string" then return "" end
    local c = bodyCache[body]
    if c then return c end
    local out = {}
    uncachedItem = false
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        local cmd, args = line:match("^(%S+)%s+(.+)$")
        if cmd and SPELL_CMDS[cmd:lower()] then
            local seq = cmd:lower() == "/castsequence"
            args = args:gsub("[^;]+", function(seg) return LocalizeSegment(seg, seq) end)
            line = cmd .. " " .. args
        end
        out[#out + 1] = line
    end
    c = table.concat(out, "\n")
    -- a translated body can outgrow the 255-letter limit (long item names): drop trailing
    -- fallback lines (the worst drinks / lowest Healthstone ranks come last) until it fits
    while #c > MAX_BODY and #out > 2 do
        out[#out] = nil
        c = table.concat(out, "\n")
    end
    -- an item name still loading ("item:<id>") is not cached: the next call has the real name
    if S.Registry and S.Registry.Class() and not uncachedItem then bodyCache[body] = c end
    return c
end
S:Listen("SPELLS_CHANGED", function() wipe(bodyCache) end)

-- The same item written three ways (the client's name, the English library name, or
-- "item:<id>" while the name was not cached) counts as equal when comparing macro bodies.
local function CanonItems(body)
    local list = {}
    for n, id in pairs(MACRO_ITEM_IDS) do
        list[#list + 1] = { n, id }
        local cn = S.Atoms.Items.Name(id)
        if type(cn) == "string" and cn ~= "" and cn ~= n and not cn:find("^item:") then list[#list + 1] = { cn, id } end
    end
    table.sort(list, function(a, b) return #a[1] > #b[1] end)   -- "Major Healthstone" before "Healthstone"
    for _, e in ipairs(list) do
        body = body:gsub((e[1]:gsub("%p", "%%%0")), "item:" .. e[2])
    end
    return body
end

--- Icon for a card: the #showtooltip / first cast spell's icon when the client
-- knows it, else the entry's texture path.
function Macros:Icon(entry)
    local spell = entry.spell and ClientName(entry.spell)
    if not spell then
        local body = self:Body(entry)
        spell = body:match("^#showtooltip ([^\n%[]+)") or body:match("/cast ([^\n;%[]+)")
        if spell then spell = spell:gsub("^!", ""):gsub("%s+$", "") end
        if spell and spell:match("^%d+$") then spell = nil end   -- "#showtooltip 13": an equipment slot
    end
    local tex = spell and Secret.Plain(S.Atoms.Spells.IconById(spell))
    return tex or entry.icon or QUESTION_MARK
end

-- First macro with this name: account macros come first (GetMacroIndexByName order).
local function Index(entry)
    local idx = Secret.Number(Secret.Call(GetMacroIndexByName, Macros:GameName(entry)))
    if idx and idx > 0 then return idx end
    return nil
end

-- Forever has no MAX_*_MACROS globals: the limits live in Constants.MacroConsts (120 / 30)
local function Limits()
    local mc = type(Constants) == "table" and type(Constants.MacroConsts) == "table" and Constants.MacroConsts or {}
    return tonumber(mc.MAX_ACCOUNT_MACROS) or tonumber(MAX_ACCOUNT_MACROS) or 120,
        tonumber(mc.MAX_CHARACTER_MACROS) or tonumber(MAX_CHARACTER_MACROS) or 30
end
Macros.Limits = Limits

local function Counts()
    local numAccount, numChar = Secret.CallMulti(GetNumMacros)
    return Secret.Number(numAccount) or 0, Secret.Number(numChar) or 0
end

-- Index of the macro called `name` in one tab ("account": 1..numAccount, "character":
-- maxAccount+1..), read by name at each index (GetMacroIndexByName only finds the first copy).
local function FindIn(name, tab)
    if not GetMacroInfo then return nil end
    local numAccount, numChar = Counts()
    local first, last = 1, numAccount
    if tab == "character" then
        local maxAccount = Limits()
        first, last = maxAccount + 1, maxAccount + numChar
    end
    for i = first, last do
        if Secret.Plain(Secret.Call(GetMacroInfo, i)) == name then return i end
    end
    return nil
end

--- Where an existing macro lives: "account" | "character" | nil (not created).
-- Character macros follow the account ones (indexes above MAX_ACCOUNT_MACROS).
function Macros:Where(entry)
    local idx = Index(entry)
    if not idx then return nil end
    return idx > (Limits()) and "character" or "account"
end

--- "missing" | "exists" | "outdated" (exists but its body differs from the library).
function Macros:Status(entry)
    local idx = Index(entry)
    if not idx then return "missing" end
    local body = Secret.Plain(Secret.Call(GetMacroBody, idx))
    local have, want = body and (body:gsub("%s+$", "")), (self:Body(entry):gsub("%s+$", ""))
    if have and have ~= want and CanonItems(have) ~= CanonItems(want) then return "outdated" end
    return "exists"
end

--- Chat line for a full macro tab ("account" | "character"), with that tab's limit.
function Macros:FullMessage(tab)
    local maxAccount, maxChar = Limits()
    if tab == "account" then
        return string.format(S.L["Your General (account) macros are full (%d). Delete one in the macro window (/macro) first."], maxAccount)
    end
    return string.format(S.L["Your character macros are full (%d). Delete one in the macro window (/macro) first."], maxChar)
end

-- ============================================================================
-- CREATE / UPDATE / MOVE
-- ============================================================================

-- A modifier-gated clause ([mod:shift]) does not run on a plain press.
local function Gated(group)
    for tok in group:sub(2, -2):gmatch("[^,]+") do
        local key = tok:match("^%s*(%a+)")
        if key == "mod" or key == "modifier" then return true end
    end
    return false
end

-- Does #showtooltip find a spell / item for the macro icon on a plain press? Yes for
-- "#showtooltip <spell or slot>" and for a /cast or /use clause that runs without a modifier.
-- Otherwise the icon stays the macro's own one, so that must not be the "?" icon.
local function ShowsSpell(body)
    if ("\n" .. body):find("\n#showtooltip[ \t]+%S") then return true end
    for line in (body .. "\n"):gmatch("([^\n]*)\n") do
        local cmd, args = line:match("^(%S+)%s+(.+)$")
        cmd = cmd and cmd:lower()
        if cmd == "/cast" or cmd == "/use" or cmd == "/castsequence" or cmd == "/castrandom" then
            for seg in args:gmatch("[^;]+") do
                local any, open = false, false
                for g in seg:gmatch("%b[]") do
                    any = true
                    if not Gated(g) then open = true end
                end
                if (not any or open) and seg:gsub("%b[]", ""):find("%S") then return true end
            end
        end
    end
    return false
end
Macros.ShowsSpell = ShowsSpell

--- Create the macro. isGeneral = account-wide (General tab: the Account section), else per
-- character (every class macro). An existing macro whose body is outdated is refreshed in
-- place ("updated"). "full" also returns the tab that is full ("account" | "character").
function Macros:Create(entry, isGeneral)
    if InCombatLockdown() then return "combat" end
    local tab = isGeneral and "account" or "character"
    if not (CreateMacro and GetMacroIndexByName) then return "full", tab end
    local status = self:Status(entry)
    if status == "outdated" then return self:Update(entry) end
    if status == "exists" then return "exists" end

    local numAccount, numChar = Counts()
    local maxAccount, maxChar = Limits()
    if (isGeneral and numAccount >= maxAccount) or (not isGeneral and numChar >= maxChar) then
        return "full", tab
    end
    local body = self:Body(entry)
    -- "?" lets #showtooltip drive the icon; a body without a spell for it gets the entry's icon
    local icon = ShowsSpell(body) and QUESTION_MARK or (entry.icon or QUESTION_MARK)
    local ok = pcall(CreateMacro, self:GameName(entry), icon, body, not isGeneral)
    if not ok then return "full", tab end
    if Index(entry) then return "created" end
    return "full", tab
end

--- Refresh an existing macro's body (keeps its slot, icon and keybinds).
function Macros:Update(entry)
    if InCombatLockdown() then return "combat" end
    local idx = Index(entry)
    if not idx then return "missing" end
    if self:Status(entry) == "exists" then return "same" end
    -- keep the icon the player picked: pass the macro's current icon (nil also keeps it)
    local _, icon = Secret.CallMulti(GetMacroInfo, idx)
    local ok = pcall(EditMacro, idx, self:GameName(entry), Secret.Plain(icon), self:Body(entry))
    return ok and "updated" or "missing"
end

--- Move a class macro that was saved as an account macro (the class "General" list did that
-- before) into this character's macros: same body, its current icon; then the account copy is
-- deleted, so other characters lose it. Only on the player's click, never in combat.
-- Returns "moved" | "combat" | "missing" (no account copy) | "full" (+ "character") | "failed".
function Macros:MoveToCharacter(entry)
    if InCombatLockdown() then return "combat" end
    if not (CreateMacro and DeleteMacro and GetMacroInfo and GetNumMacros) then return "failed" end
    local name = self:GameName(entry)
    local acc = FindIn(name, "account")
    if not acc then return "missing" end
    local _, icon, body = Secret.CallMulti(GetMacroInfo, acc)
    icon, body = Secret.Plain(icon), Secret.Plain(body)
    if type(body) ~= "string" then return "failed" end
    if not FindIn(name, "character") then
        local _, numChar = Counts()
        local _, maxChar = Limits()
        if numChar >= maxChar then return "full", "character" end
        if not pcall(CreateMacro, name, icon or QUESTION_MARK, body, true) then return "failed" end
        if not FindIn(name, "character") then return "failed" end
    end
    -- creating a macro can shift indexes: find the account copy again (by name) right before deleting
    acc = FindIn(name, "account")
    if acc then pcall(DeleteMacro, acc) end
    if FindIn(name, "account") then return "failed" end
    return "moved"
end

--- Refresh every outdated LazyGCore macro of this class and the account list. Returns the count
-- updated (0, "combat" in combat: macros can't be edited there).
function Macros:UpdateAll()
    if InCombatLockdown() then return 0, "combat" end
    local n = 0
    local function Walk(list)
        for _, e in ipairs(list or {}) do
            if self:Update(e) == "updated" then n = n + 1 end
        end
    end
    local lib = self:Library()
    if lib then
        Walk(lib.general)
        for _, list in pairs(lib.pve or {}) do Walk(list) end
        Walk(lib.pvp)
    end
    Walk(ACCOUNT)
    return n
end

-- ============================================================================
-- SLASH
-- ============================================================================

--- "Update created macros" (slash and Macros page): print the count, or the in-combat message.
function Macros:PrintUpdateAll()
    local n, why = self:UpdateAll()
    if why == "combat" then
        S:Print(S.L["Can't change macros in combat."])
    else
        S:Print(string.format(S.L["Updated %d macro(s)."], n))
    end
end

S.Commands:Register("macros", function(arg)
    arg = (arg or ""):lower()
    if arg == "update" then
        Macros:PrintUpdateAll()
    else
        S:Fire("OPEN_PAGE", "macros")
    end
end, "Open the macro library ('update' refreshes created macros)", { "macro" })
