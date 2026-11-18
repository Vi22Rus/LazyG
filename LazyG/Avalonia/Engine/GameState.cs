using System;
using System.Collections.Generic;

namespace LazyG.Desktop.Engine;

// RGB transport remains versioned and separate from this immutable game snapshot.
// Never encode "unknown" as zero/false. Unknown cannot satisfy an action gate.
internal enum Knowledge { Unknown, Known, Protected, Stale }
internal enum Truth { False, True, Unknown }

internal readonly record struct Observed<T>(T? Value, Knowledge Quality, DateTimeOffset UpdatedAt)
    where T : struct
{
    public static Observed<T> Known(T value, DateTimeOffset now) => new(value, Knowledge.Known, now);
    public static Observed<T> Missing(Knowledge reason = Knowledge.Unknown) => new(null, reason, default);
    public Observed<T> At(DateTimeOffset now, TimeSpan maxAge) =>
        Quality == Knowledge.Known && now - UpdatedAt > maxAge
            ? this with { Quality = Knowledge.Stale }
            : this;
    public Truth Is(Func<T,bool> predicate) =>
        Quality == Knowledge.Known && Value.HasValue
            ? predicate(Value.Value) ? Truth.True : Truth.False
            : Truth.Unknown;
}

internal sealed record GameState(
    string Client,
    DateTimeOffset CapturedAt,
    Knowledge Transport,
    Observed<int> ClassId,
    Observed<int> RaceId,
    Observed<int> Level,
    Observed<int> SpecIndex,
    Observed<bool> InCombat,
    Observed<bool> TargetExists,
    Observed<bool> TargetHostile,
    Observed<bool> TargetAlive,
    Observed<int> PlayerHealthPercent,
    Observed<int> TargetHealthPercent,
    Observed<int> PowerPercent,
    Observed<bool> Moving,
    Observed<bool> Casting,
    Observed<int> GcdRemainingMilliseconds,
    IReadOnlyDictionary<int,SpellState> Spells,
    IReadOnlyDictionary<AuraKey,AuraState> Auras)
{
    public static GameState Empty(DateTimeOffset now) => new(
        "forever",now,Knowledge.Unknown,
        Observed<int>.Missing(),Observed<int>.Missing(),Observed<int>.Missing(),
        Observed<int>.Missing(),Observed<bool>.Missing(),Observed<bool>.Missing(),
        Observed<bool>.Missing(),Observed<bool>.Missing(),Observed<int>.Missing(),
        Observed<int>.Missing(),Observed<int>.Missing(),Observed<bool>.Missing(),
        Observed<bool>.Missing(),Observed<int>.Missing(),
        new Dictionary<int,SpellState>(),new Dictionary<AuraKey,AuraState>());

    // A snapshot is valid only for its explicitly observed fields. Never infer
    // HP, aura, GCD, cooldown, or usability from an RGB v2 status flag.
    public GameState Age(DateTimeOffset now, TimeSpan maxAge) => this with
    {
        Transport = now - CapturedAt > maxAge ? Knowledge.Stale : Transport,
        ClassId=ClassId.At(now,maxAge),RaceId=RaceId.At(now,maxAge),
        Level=Level.At(now,maxAge),SpecIndex=SpecIndex.At(now,maxAge),
        InCombat=InCombat.At(now,maxAge),TargetExists=TargetExists.At(now,maxAge),
        TargetHostile=TargetHostile.At(now,maxAge),TargetAlive=TargetAlive.At(now,maxAge),
        PlayerHealthPercent=PlayerHealthPercent.At(now,maxAge),
        TargetHealthPercent=TargetHealthPercent.At(now,maxAge),
        PowerPercent=PowerPercent.At(now,maxAge),Moving=Moving.At(now,maxAge),
        Casting=Casting.At(now,maxAge),GcdRemainingMilliseconds=GcdRemainingMilliseconds.At(now,maxAge),
        Spells=AgeSpells(Spells,now,maxAge), Auras=AgeAuras(Auras,now,maxAge)
    };
    private static IReadOnlyDictionary<int,SpellState> AgeSpells(
        IReadOnlyDictionary<int,SpellState> source,DateTimeOffset now,TimeSpan ttl)
    {
        var result=new Dictionary<int,SpellState>();
        foreach(var pair in source)
            result[pair.Key]=pair.Value with
            {
                Learned=pair.Value.Learned.At(now,ttl),
                Usable=pair.Value.Usable.At(now,ttl),
                InRange=pair.Value.InRange.At(now,ttl),
                CooldownMs=pair.Value.CooldownMs.At(now,ttl),
                Charges=pair.Value.Charges.At(now,ttl)
            };
        return result;
    }
    private static IReadOnlyDictionary<AuraKey,AuraState> AgeAuras(
        IReadOnlyDictionary<AuraKey,AuraState> source,DateTimeOffset now,TimeSpan ttl)
    {
        var result=new Dictionary<AuraKey,AuraState>();
        foreach(var pair in source)
            result[pair.Key]=pair.Value with
            {
                Present=pair.Value.Present.At(now,ttl),
                Stacks=pair.Value.Stacks.At(now,ttl),
                RemainingMs=pair.Value.RemainingMs.At(now,ttl)
            };
        return result;
    }
}
// Range evidence is never a precise HP value; 0-4 includes both living and dead.
internal readonly record struct HealthBand(int Lower, int Upper)
{
    public bool IsValid => Lower>=0 && Upper<=100 && Lower<=Upper;
    public static bool TryParse(string? text,out HealthBand band)
    {
        band=default;
        if(string.IsNullOrWhiteSpace(text))return false;
        var parts=text.Replace('–','-').Replace("%","").Split('-');
        if(parts.Length!=2 || !int.TryParse(parts[0],out int lo) ||
           !int.TryParse(parts[1],out int hi))return false;
        var candidate=new HealthBand(lo,hi);
        if(!candidate.IsValid)return false;
        band=candidate;
        return true;
    }
}

// RGB v2 reports positive flags only; an absent flag cannot distinguish
// 'false' from 'the secret API could not be read'. V3 may confirm dead=true.
internal static class TargetLifeDecoder
{
    public static Observed<bool> Alive(bool targetExists,bool v2AliveBit,
        bool v3DeadConfirmed,DateTimeOffset now)
    {
        if(!targetExists)return Observed<bool>.Missing();
        if(v2AliveBit && v3DeadConfirmed)return Observed<bool>.Missing(); // conflicting frames
        if(v3DeadConfirmed)return Observed<bool>.Known(false,now);
        if(v2AliveBit)return Observed<bool>.Known(true,now);
        return Observed<bool>.Missing();
    }
}

internal sealed record SpellState(
    Observed<bool> Learned,
    Observed<bool> Usable,
    Observed<bool> InRange,
    Observed<int> CooldownMs,
    Observed<int> Charges);

internal readonly record struct AuraKey(string UnitId, int SpellId, bool IsDebuff);
internal sealed record AuraState(
    Observed<bool> Present,
    Observed<int> Stacks,
    Observed<int> RemainingMs);

internal static class TruthLogic
{
    public static Truth Not(Truth x) => x switch
    {
        Truth.True=>Truth.False,Truth.False=>Truth.True,_=>Truth.Unknown
    };
    public static Truth And(params Truth[] values)
    {
        bool unknown=false;
        foreach(var x in values)
        {
            if(x==Truth.False)return Truth.False;
            if(x==Truth.Unknown)unknown=true;
        }
        return unknown?Truth.Unknown:Truth.True;
    }
    public static Truth Or(params Truth[] values)
    {
        bool unknown=false;
        foreach(var x in values)
        {
            if(x==Truth.True)return Truth.True;
            if(x==Truth.Unknown)unknown=true;
        }
        return unknown?Truth.Unknown:Truth.False;
    }
    public static Truth AtLeast(int count,params Truth[] values)
    {
        if(count<=0)return Truth.True;
        int yes=0,maybe=0;
        foreach(var x in values) {if(x==Truth.True)yes++;if(x==Truth.Unknown)maybe++;}
        if(yes>=count)return Truth.True;
        return yes+maybe<count?Truth.False:Truth.Unknown;
    }
}

internal static class ConditionEvaluator
{
    public static Truth InCombat(GameState s) => s.InCombat.Is(x=>x);
    public static Truth HasTarget(GameState s) => s.TargetExists.Is(x=>x);
    public static Truth TargetHostile(GameState s) => s.TargetHostile.Is(x=>x);
    public static Truth TargetAlive(GameState s) => s.TargetAlive.Is(x=>x);
    public static Truth HealthBelow(GameState s,int percent) => s.PlayerHealthPercent.Is(x=>x<percent);
    public static Truth TargetBelow(GameState s,int percent) => s.TargetHealthPercent.Is(x=>x<percent);
    public static Truth PowerAbove(GameState s,int percent) => s.PowerPercent.Is(x=>x>=percent);
    public static Truth IsMoving(GameState s) => s.Moving.Is(x=>x);
    public static Truth GcdReady(GameState s) => s.GcdRemainingMilliseconds.Is(x=>x<=0);
    // Global invariant for all hostile single-target attack and execute logic.
    // No target, corpse, missing death evidence, unknown hostility => no cast.
    public static Truth AttackTarget(GameState s) =>
        TruthLogic.And(s.Transport==Knowledge.Known?Truth.True:Truth.Unknown,
            HasTarget(s),TargetHostile(s),TargetAlive(s));
    public static bool CanRecommendTargetedAttack(GameState s,int spellId,
        params Truth[] additionalConditions)
    {
        if(AttackTarget(s)!=Truth.True || SpellReady(s,spellId)!=Truth.True)return false;
        return CanRecommend(additionalConditions);
    }
    // Entire 5% band must satisfy the threshold. This NEVER equates 0-4% to
    // a nonzero value or presumes the target alive.
    public static Truth TargetBelowBand(Observed<HealthBand> band,int threshold) =>
        band.Quality==Knowledge.Known && band.Value is HealthBand value && value.IsValid &&
        threshold>0 && threshold<=100
            ? value.Upper<threshold ? Truth.True : Truth.False : Truth.Unknown;
    public static bool CanRecommendExecute(GameState s,int spellId,
        Observed<HealthBand> targetBand,int threshold) =>
        CanRecommendTargetedAttack(s,spellId,TargetBelowBand(targetBand,threshold));

    public static Truth SpellReady(GameState s,int spellId)
    {
        if(!s.Spells.TryGetValue(spellId,out var spell))return Truth.Unknown;
        return TruthLogic.And(spell.Learned.Is(x=>x),spell.Usable.Is(x=>x),
            spell.CooldownMs.Is(x=>x<=0));
    }
    public static Truth HasAura(GameState s,AuraKey key)
    {
        return s.Auras.TryGetValue(key,out var aura) ? aura.Present.Is(x=>x):Truth.Unknown;
    }
    // Default policy: an unknown requirement never authorizes a cast.
    public static bool CanRecommend(params Truth[] requirements) =>
        TruthLogic.And(requirements)==Truth.True;
}
