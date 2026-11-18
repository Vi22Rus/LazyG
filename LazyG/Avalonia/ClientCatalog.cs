using System.Text.Json;
namespace LazyG.Desktop;
internal sealed record Specialization(string Id, string Name, string Icon);
internal sealed record GameClass(string Id, string Name, string Icon, string Accent, Specialization[] Specs);
internal sealed record GameClient(string Id, string Name, string GameLine, bool Available, GameClass[] Classes);
internal static class ClientCatalog
{
    private static Specialization S(string id, string title, string icon) => new(id,title,icon);
    // Forever catalog is explicitly separate from other expansion/client catalogs.
    public static readonly GameClient Forever = new("forever", "WoW Forever", "Forever · 1.60.x", true,
    [
        new("warrior","Warrior","Warrior","#C5A36B",[S("arms","Arms","Warrior_Arms"),S("fury","Fury","Warrior_Fury"),S("protection","Protection","Warrior_Protection")]),
        new("paladin","Paladin","Paladin","#F39CC6",[S("holy","Holy","Paladin_Holy"),S("protection","Protection","Paladin_Protection"),S("retribution","Retribution","Paladin_Retribution")]),
        new("hunter","Hunter","Hunter","#A4BD77",[S("beast-mastery","Beast Mastery","Hunter_BeastMastery"),S("marksmanship","Marksmanship","Hunter_Marksmanship"),S("survival","Survival","Hunter_Survival")]),
        new("rogue","Rogue","Rogue","#F9DF74",[S("assassination","Assassination","Rogue_Assassination"),S("combat","Combat","Rogue_Combat"),S("subtlety","Subtlety","Rogue_Subtlety")]),
        new("priest","Priest","Priest","#E3DDE2",[S("discipline","Discipline","Priest_Discipline"),S("holy","Holy","Priest_Holy"),S("shadow","Shadow","Priest_Shadow")]),
        new("shaman","Shaman","Shaman","#5A9FFF",[S("elemental","Elemental","Shaman_Elemental"),S("enhancement","Enhancement","Shaman_Enhancement"),S("restoration","Restoration","Shaman_Restoration")]),
        new("mage","Mage","Mage","#83D5F4",[S("arcane","Arcane","Mage_Arcane"),S("fire","Fire","Mage_Fire"),S("frost","Frost","Mage_Frost")]),
        new("warlock","Warlock","Warlock","#AA91E5",[S("affliction","Affliction","Warlock_Affliction"),S("demonology","Demonology","Warlock_Demonology"),S("destruction","Destruction","Warlock_Destruction")]),
        new("druid","Druid","Druid","#F2A74A",[S("balance","Balance","Druid_Balance"),S("feral","Feral Combat","Druid_Feral"),S("restoration","Restoration","Druid_Restoration")])
    ]);
    public static readonly GameClient[] Clients =
    [
        Forever,
        new("wotlk","Wrath of the Lich King 3.3.5","Classic · 3.3.5",false,[]),
        new("mop","Mists of Pandaria","Classic / MoP",false,[]),
        new("retail","Retail","Modern WoW",false,[])
    ];
}
internal sealed class UserSession
{
    public string LastClient { get; set; } = "forever";
    public string LastClass { get; set; } = "";
    public string LastSpec { get; set; } = "";
    public string ForeverAddonsPath { get; set; } = "";
    public bool ForeverConfigured { get; set; }
    private static string Pathname => System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),"LazyG","ui-state.json");
    public static UserSession Load()
    {
        try { return JsonSerializer.Deserialize<UserSession>(File.ReadAllText(Pathname)) ?? new(); }
        catch (Exception) { return new(); }
    }
    public void Save()
    {
        try
        {
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(Pathname)!);
            File.WriteAllText(Pathname, JsonSerializer.Serialize(this));
        }
        catch (IOException) { } catch (UnauthorizedAccessException) { }
    }
}