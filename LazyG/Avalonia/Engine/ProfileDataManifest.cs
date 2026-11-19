using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace LazyG.Desktop.Engine;

// Build-time/runtime contract of the game facts requested by one XML profile.
// No pixel coordinates or game input live here; transport must negotiate this
// manifest before supplying indexed ability/aura blocks.
internal sealed record SpellFamilyRequirement(int BaseSpellId,IReadOnlyList<int> RankSpellIds);
internal sealed record AuraFamilyRequirement(string Unit,bool Debuff,IReadOnlyList<int> RankSpellIds);
internal sealed record ProfileDataManifest(
    string Client,int ClassId,int SpecIndex,string Mode,
    uint LayoutHash,IReadOnlyList<SpellFamilyRequirement> SpellFamilies,
    IReadOnlyList<AuraFamilyRequirement> AuraFamilies,
    IReadOnlyList<string> Signals)
{
    public bool CompatibleWith(string client,int classId,int specIndex,string mode,uint hash)=>
        Client==client && ClassId==classId && SpecIndex==specIndex &&
        Mode==mode && LayoutHash==hash;
}

internal static class ProfileDataManifestBuilder
{
    // This only describes verified schema/rank-family membership, not learned
    // ranks, readiness or aura presence in the player's current game state.
    public static ProfileDataManifest Build(RotationProfileV2 profile)
    {
        if(profile.Client!="forever")throw new FormatException("Manifest client");
        var spells=new List<SpellFamilyRequirement>();
        var auras=new List<AuraFamilyRequirement>();
        var signals=new SortedSet<string>(StringComparer.Ordinal) {
            "Identity","TargetExists","TargetHostile","TargetAlive","GcdActive"
        };
        var seenSpells=new HashSet<int>();
        var seenAuras=new HashSet<string>(StringComparer.Ordinal);
        foreach(var rule in profile.Rules.OrderBy(r=>r.Priority))
        {
            if(seenSpells.Add(rule.SpellId))
            {
                int[] ids=profile.ClassId==3
                    ? ForeverHunterAbilityCatalog.Ranks(rule.SpellId):Array.Empty<int>();
                if(ids.Length==0)ids=new[]{rule.SpellId};
                if(ids.Distinct().Count()!=ids.Length || ids.Any(id=>id<=0))
                    throw new FormatException("Invalid rank family");
                spells.Add(new(rule.SpellId,Array.AsReadOnly(ids)));
            }
            foreach(var condition in rule.Conditions)
            {
                if(condition.Signal=="TargetDebuffAbsent")
                {
                    var ids=(condition.AuraRanks??
                        new[]{condition.AuraSpellId??throw new FormatException("Aura ID")})
                        .ToArray();
                    if(ids.Length==0 || ids.Any(id=>id<=0) ||
                       ids.Distinct().Count()!=ids.Length)
                        throw new FormatException("Invalid aura IDs");
                    string key="target:debuff:"+string.Join(",",ids);
                    if(seenAuras.Add(key))
                        auras.Add(new("target",true,Array.AsReadOnly(ids)));
                    signals.Add("TargetEpoch");
                }
                else if(condition.Signal=="PowerPercent")
                    signals.Add("PowerBand5");
                else if(condition.Signal is "PlayerHealthPercent" or "TargetHealthPercent")
                    signals.Add(condition.Signal+"BandOrExact");
                else throw new FormatException("Unrecognized manifest signal");
            }
        }
        // Fixed ordering is part of the wire schema. Spell IDs remain concrete,
        // priority changes and UI settings never change indexed wire meaning.
        spells.Sort((a,b)=>a.BaseSpellId.CompareTo(b.BaseSpellId));
        auras.Sort((a,b)=>a.RankSpellIds[0].CompareTo(b.RankSpellIds[0]));
        if(spells.Count>100 || auras.Count>100)
            throw new FormatException("Manifest capacity");
        string canonical="LazyG.ProfileDataManifest.v1|"+profile.Client+"|"+
            profile.ClassId+"|"+profile.SpecIndex+"|"+profile.Mode+"|"+
            string.Join(";",spells.Select(x=>x.BaseSpellId+":"+
                string.Join(",",x.RankSpellIds)))+"|"+
            string.Join(";",auras.Select(x=>x.Unit+":"+(x.Debuff?"D":"B")+":"+
                string.Join(",",x.RankSpellIds)))+"|"+
            string.Join(",",signals);
        uint hash=2166136261;
        foreach(byte c in Encoding.UTF8.GetBytes(canonical))
        {
            hash^=c;
            hash*=16777619;
        }
        return new(profile.Client,profile.ClassId,profile.SpecIndex,profile.Mode,
            hash,spells.AsReadOnly(),auras.AsReadOnly(),signals.ToArray());
    }
}
