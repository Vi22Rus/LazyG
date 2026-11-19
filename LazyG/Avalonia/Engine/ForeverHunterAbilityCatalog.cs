using System;
using System.Collections.Generic;
using System.Linq;

namespace LazyG.Desktop.Engine;

// Original LazyG data registry, cross-checked against user-provided
// Sonah/Classes/Hunter.lua. IDs/relationships are reference candidates:
// known game facts still require current Forever-client validation.
// Never infer learned/usable from catalog membership.
internal sealed record ForeverHunterAbility(
    string Key,int BaseSpellId,IReadOnlyList<int> CandidateRanks,
    string Kind,string Target,string? SharedCooldownGroup=null,
    bool RequiresPet=false,bool RequiresTargetAura=false);

internal static class ForeverHunterAbilityCatalog
{
    private static ForeverHunterAbility A(string key,string kind,string target,
        string? shared,bool pet,bool targetAura,params int[] ids)=>
        new(key,ids[0],Array.AsReadOnly(ids),kind,target,shared,pet,targetAura);

    private static readonly ForeverHunterAbility[] Data = {
        A("AutoShot","AutoRepeat","target",null,false,false,75),
        A("ArcaneShot","Shot","target","arcane",false,false,
            3044,14281,14282,14283,14284,14285,14286,14287),
        A("AimedShot","Shot","target","shot",false,false,
            19434,20900,20901,20902,20903,20904),
        A("MultiShot","Shot","target","shot",false,false,2643),
        A("SerpentSting","Debuff","target",null,false,true,
            1978,13549,13550,13551,13552,13553,13554,13555,25295),
        A("HuntersMark","Debuff","target",null,false,true,1130,14323,14324,14325),
        A("SummonHawk","Summon","target","arcane",false,false,
            1293241,1293525,1293526,1293527),
        A("RapidFire","SelfBuff","player",null,false,false,3045),
        A("BestialWrath","PetBuff","pet",null,true,false,19574),
        A("Intimidation","PetAttack","target",null,true,false,19577),
        A("RaptorStrike","Melee","target",null,false,false,
            2973,14260,14261,14262,14263,14264,14265,14266),
        A("MongooseBite","Melee","target",null,false,false,
            1495,14269,14270,14271),
        A("Attack","AutoRepeat","target",null,false,false,6603),
        A("ConcussiveShot","Debuff","target",null,false,true,5116),
        A("ScorpidSting","Debuff","target",null,false,true,3043),
        A("ViperSting","Debuff","target",null,false,true,3034,14279,14280),
        A("AspectHawk","SelfBuff","player",null,false,false,
            13165,14318,14319,14320,14321,14322,25296),
        A("AspectMonkey","SelfBuff","player",null,false,false,13163),
        A("AspectBeast","SelfBuff","player",null,false,false,
            13161,1299445,1299446,1299447),
        A("AspectCheetah","SelfBuff","player",null,false,false,5118),
        A("AspectPack","SelfBuff","player",null,false,false,13159),
        A("AspectWild","SelfBuff","player",null,false,false,20043,20190),
        A("MendPet","PetHeal","pet",null,true,false,
            136,3111,3661,3662,13542,13543,13544),
        A("RevivePet","PetUtility","pet",null,true,false,982),
        A("CallPet","PetUtility","pet",null,true,false,883),
        A("FeignDeath","Defensive","player",null,false,false,5384),
        A("Deterrence","Defensive","player",null,false,false,19263),
        A("ImmolationTrap","Trap","player","trap",false,false,
            13795,14302,14303,14304,14305),
        A("ExplosiveTrap","Trap","player","trap",false,false,
            13813,14316,14317),
        A("FreezingTrap","Trap","player","trap",false,false,
            1499,14310,14311),
        A("FrostTrap","Trap","player","trap",false,false,13809),
        A("WingClip","Debuff","target",null,false,true,2974,14267,14268),
        A("ScatterShot","Control","target",null,false,false,19503),
        A("Disengage","Defensive","player",null,false,false,781,14272,14273),
        A("Lacerate","MeleeDebuff","target",null,false,true,
            24118,24119,24120,1299332),
        A("StriderKick","Melee","target",null,false,false,1317257),
        A("Counterattack","Melee","target",null,false,false,
            19306,1242634,20909,20910),
        A("SniperShot","Shot","target",null,false,false,
            1310687,1310785,1310786),
        A("TrueshotAura","SelfBuff","player",null,false,false,
            1299346,1299348,19506,20905,20906)
    };
    private static readonly IReadOnlyDictionary<int,ForeverHunterAbility> ByBase;
    static ForeverHunterAbilityCatalog()
    {
        var bases=new Dictionary<int,ForeverHunterAbility>();
        var ranks=new HashSet<int>();
        foreach(var ability in Data)
        {
            if(!bases.TryAdd(ability.BaseSpellId,ability) ||
               ability.CandidateRanks.Count==0 ||
               ability.CandidateRanks[0]!=ability.BaseSpellId ||
               ability.CandidateRanks.Any(id=>id<=0 || id>16777215 ||
                   !ranks.Add(id)))
                throw new InvalidOperationException("Duplicate/invalid Hunter rank registry");
        }
        ByBase=bases;
    }
    public static IReadOnlyList<ForeverHunterAbility> All=>Array.AsReadOnly(Data);
    public static ForeverHunterAbility? Find(int baseSpellId)=>
        ByBase.TryGetValue(baseSpellId,out var ability)?ability:null;
    public static int[] Ranks(int baseSpellId)=>
        Find(baseSpellId) is { } ability?ability.CandidateRanks.ToArray():Array.Empty<int>();
}
