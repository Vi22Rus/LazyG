-- Template: talent advice per class (World of Warcraft: Forever, launch 1.60.1)
-- Pure data. For each class, LazyGCore's pick for each kind of content: the spec key and the build
-- name (both must exist in that class's template; the talents review checks it) plus one short
-- tip that says why. UI/TalentPopup shows them in the Build Browser ("LazyGCore's picks") and stars
-- the recommended builds in the list.
--   kinds: leveling, dungeon, raid, pvp (shown in this order)
-- Tips are locale keys (Locale/*.lua).

local S = LazyGCore

S.TalentAdvice = {
    order = { "leveling", "dungeon", "raid", "pvp" },
    WARRIOR = {
        -- Fury kills questing mobs 6-14 % faster than Arms at 20-60 (sim, launch model, 300 fights per level)
        leveling = { spec = "Fury", build = "Leveling 10-60 (17/34/0)",
            tip = "Fury: two one-handers with Bloodthirst, Whirlwind and Flurry kill fastest while leveling. Arms before you can dual wield (20)." },
        dungeon = { spec = "ProtectionWar", build = "Endgame PvE Tank (6/5/40)",
            tip = "Groups need tanks: Protection holds packs with Thunder Clap, Shield Slam and Revenge. Go Fury if you join as damage." },
        raid = { spec = "Fury", build = "Endgame PvE (17/34/0)",
            tip = "Fury: two weapons with Bloodthirst, Flurry and Whirlwind for the most boss damage. Raid tanks stay Protection." },
        pvp = { spec = "Arms", build = "PvP (31/20/0)",
            tip = "Arms: Mortal Strike halves the healing your target takes - the warrior pick for battlegrounds and duels." },
    },
    PALADIN = {
        leveling = { spec = "Retribution", build = "Leveling 10-60 (12/8/31)",
            tip = "Retribution: Seal of Command and Unsealed Wrath hit hard, and you heal yourself instead of resting." },
        dungeon = { spec = "Protection", build = "Endgame PvE (0/44/7)",
            tip = "Protection: Consecration and Holy Shield hold whole packs. Holy if your group needs a healer." },
        raid = { spec = "HolyPal", build = "Endgame PvE (31/9/11)",
            tip = "Holy: big, mana-efficient heals on the tanks with Holy Shock and Light's Vigil." },
        pvp = { spec = "Retribution", build = "PvP (9/0/42)",
            tip = "Retribution: Seal of Command bursts and Repentance controls. Holy if you want to heal in battlegrounds." },
    },
    HUNTER = {
        leveling = { spec = "BeastMastery", build = "Leveling 10-60 (31/20/0)",
            tip = "Beast Mastery: your pet tanks and Bestial Wrath kills fast - the easiest way to level." },
        dungeon = { spec = "Marksmanship", build = "Endgame PvE (0/38/13)",
            tip = "Marksmanship: steady ranged damage, Trueshot Aura for the group and Barrage on packs." },
        raid = { spec = "Marksmanship", build = "Endgame PvE (0/38/13)",
            tip = "Marksmanship: the strongest sustained ranged damage, and Trueshot Aura helps the raid." },
        pvp = { spec = "Survival", build = "PvP (7/5/39)",
            tip = "Survival: Counterattack, Deterrence and Entrapment keep melee off you." },
    },
    ROGUE = {
        leveling = { spec = "Combat", build = "Leveling 10-60 (16/35/0)",
            tip = "Combat: Sinister Strike, Shank and Adrenaline Rush with any weapon - fast kills, few deaths." },
        dungeon = { spec = "Combat", build = "Endgame PvE (16/35/0)",
            tip = "Combat: Blade Flurry is the best rogue damage on packs." },
        raid = { spec = "Assassination", build = "Endgame PvE (36/10/5)",
            tip = "Assassination: Mutilate and the stronger launch poisons for steady boss damage." },
        pvp = { spec = "Subtlety", build = "PvP (3/17/31)",
            tip = "Subtlety: Premeditation, Preparation and Death Mark for the hardest openers." },
    },
    PRIEST = {
        leveling = { spec = "Shadow", build = "Leveling 10-60 (15/0/36)",
            tip = "Shadow: Spirit Tap, DoTs and Mind Flay - very little drinking between fights." },
        dungeon = { spec = "Holy", build = "Endgame PvE (16/35/0)",
            tip = "Holy: Prayer of Healing and Holy Nova keep a whole group up. Discipline works too." },
        raid = { spec = "Holy", build = "Endgame PvE (16/35/0)",
            tip = "Holy: the strongest group and raid healing." },
        pvp = { spec = "Discipline", build = "PvP (36/15/0)",
            tip = "Discipline: Penance, strong shields and Power Infusion. Shadow if you want damage." },
    },
    SHAMAN = {
        leveling = { spec = "Enhancement", build = "Leveling 10-60 (17/34/0)",
            tip = "Enhancement: Stormstrike every 8 seconds with Flurry and Windfury, and you heal yourself between pulls." },
        dungeon = { spec = "RestorationSham", build = "Endgame PvE (0/10/41)",
            tip = "Restoration: Chain Heal and totems - groups always look for one." },
        raid = { spec = "RestorationSham", build = "Endgame PvE (0/10/41)",
            tip = "Restoration: Chain Heal and Mana Tide Totem, the shaman role raids want most." },
        pvp = { spec = "Elemental", build = "PvP (34/17/0)",
            tip = "Elemental: the stronger launch shocks give big burst. Restoration if you heal." },
    },
    MAGE = {
        leveling = { spec = "Frost", build = "Leveling AoE grind 10-60 (0/3/48)",
            tip = "Frost: slows and Frost Nova keep mobs off you; this build pulls whole packs from about 30." },
        dungeon = { spec = "Frost", build = "Endgame PvE Shatter (0/3/48)",
            tip = "Frost: Blizzard and Cone of Cold on packs, and control when a pull goes wrong." },
        -- raid boss 60, max gear (sim, launch model): Arcane 856, Frost 772, Fire 730 DPS (Fire runs dry)
        raid = { spec = "Arcane", build = "Endgame PvE (38/10/3)",
            tip = "Arcane: Arcane Blast stacks with Arcane Power and Presence of Mind - the most boss damage, and mana that lasts the whole fight." },
        pvp = { spec = "Frost", build = "PvP Frost control (10/0/41)",
            tip = "Frost: Shatter combos, Ice Block and Ice Barrier." },
    },
    WARLOCK = {
        leveling = { spec = "Affliction", build = "Leveling 10-60 Drain-tank (46/5/0)",
            tip = "Affliction: DoTs and drains keep you topped up - almost no downtime." },
        dungeon = { spec = "Destruction", build = "Endgame PvE (5/11/35)",
            tip = "Destruction: Shadow Bolt and Incinerate damage, Rain of Fire on packs." },
        raid = { spec = "Destruction", build = "Endgame PvE (5/11/35)",
            tip = "Destruction: the most single-target damage." },
        pvp = { spec = "Affliction", build = "PvP (44/5/2)",
            tip = "Affliction: DoTs, fears and drains wear players down." },
    },
    DRUID = {
        leveling = { spec = "Feral", build = "Leveling 10-60 (0/37/14)",
            tip = "Feral: Cat Form kills fast, Bear Form saves bad pulls, Travel Form between quests." },
        dungeon = { spec = "Feral", build = "Endgame PvE Bear (0/43/8)",
            tip = "Feral Bear: tanks packs with Swipe and Lacerate. Restoration if you heal." },
        raid = { spec = "Restoration", build = "Endgame PvE (6/0/45)",
            tip = "Restoration: HoTs, Wild Growth and Swiftmend - raids always want druid healers." },
        pvp = { spec = "Feral", build = "PvP Cat (0/30/21)",
            tip = "Feral: shift out of roots and snares. Restoration is a strong battleground healer." },
    },
}
