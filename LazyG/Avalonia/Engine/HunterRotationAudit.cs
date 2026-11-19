using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

namespace LazyG.Desktop.Engine;

// WoW Forever Hunter families independently cross-checked against the Hunter reference
// rank lists. No rank is presumed learned from level; prove learned from a fresh observation.
internal static class HunterSpellFamilies
{
    private static readonly IReadOnlyDictionary<int,int[]> Families=new Dictionary<int,int[]> {
        [1130]=new[] {1130,14323,14324,14325}, // Hunter's Mark
        [1978]=new[] {1978,13549,13550,13551,13552,13553,13554,13555,25295}, // Serpent Sting
        [3044]=new[] {3044,14281,14282,14283,14284,14285,14286,14287}, // Arcane Shot; higher variants need game verification
        [75]=new[] {75} // Auto Shot
    };
    public static int[] Ranks(int baseSpellId) =>
        Families.TryGetValue(baseSpellId,out var ids)?(int[])ids.Clone():Array.Empty<int>();
    public static int? BaseId(int spellId) =>
        Families.FirstOrDefault(kv=>kv.Value.Contains(spellId)).Key is int n && n>0?n:null;

    public static HunterRankFinding Find(GameState state,int baseSpellId,DateTimeOffset now)
    {
        var ranks=Ranks(baseSpellId);
        if(ranks.Length==0)return new(baseSpellId,null,"UnknownFamily");
        var fresh=state.Age(now,TimeSpan.FromMilliseconds(900));
        if(fresh.Transport!=Knowledge.Known || fresh.ClassId.Is(v=>v==3)!=Truth.True)
            return new(baseSpellId,null,"NoFreshHunterIdentity");
        // Higher ranks are chosen only among explicitly Known(true) learned flags.
        // If any rank has no observation, a newer rank may exist: cannot assert best rank.
        foreach(int rank in ranks)
            if(!fresh.Spells.TryGetValue(rank,out var spell) ||
               spell.Learned.Quality!=Knowledge.Known)
                return new(baseSpellId,null,"RankSetUnverified");
        var best=ranks.LastOrDefault(rank=>fresh.Spells[rank].Learned.Value==true);
        return best>0?new(baseSpellId,best,"VerifiedLearnedRank"):
            new(baseSpellId,null,"NoKnownLearnedRank");
    }
}
internal sealed record HunterRankFinding(int BaseSpellId,int? SelectedRank,string Status);

// Diagnostic-only audit: predicted rotations and *trusted observed* cast events are
// different channels; absence of combat events is never labeled wrong execution.
internal enum RotationAuditVerdict { Unobservable, Match, Mismatch, Blocked, EventOnly }
internal enum RotationCastEvidence { None, UnitSpellcastSucceeded, CombatLogSuccess }
// TargetEpoch is only meaningful when both sides independently prove it.
internal sealed record RotationObservedCast(int SpellId,DateTimeOffset At,
    RotationCastEvidence Evidence,int? TargetEpoch,bool PlayerConfirmed=false);
internal sealed record RotationAuditRow(DateTimeOffset At,int? ExpectedSpellId,
    string? ExpectedRule, int? ObservedSpellId,RotationAuditVerdict Verdict,
    string Reason,string[] Conditions,int? TargetEpoch=null);

internal static class HunterAuditReadiness
{
    // Fully separate diagnostic matrix: no Known value is inferred from missing fields.
    public static string[] Missing(GameState state,DateTimeOffset now)
    {
        var fresh=state.Age(now,TimeSpan.FromMilliseconds(900));
        var gaps=new List<string>();
        if(fresh.Transport!=Knowledge.Known)gaps.Add("RgbTransport");
        if(fresh.ClassId.Is(x=>x==3)!=Truth.True)gaps.Add("HunterIdentity");
        if(fresh.SpecIndex.Is(x=>x==1)!=Truth.True)gaps.Add("BeastMasteryIdentity");
        if(fresh.TargetExists.Is(x=>x)!=Truth.True ||
           fresh.TargetHostile.Is(x=>x)!=Truth.True ||
           fresh.TargetAlive.Is(x=>x)!=Truth.True)gaps.Add("HostileLivingTarget");
        if(fresh.GcdRemainingMilliseconds.Is(x=>x<=0)!=Truth.True)gaps.Add("GcdReady");
        if(fresh.PowerBand.Quality!=Knowledge.Known ||
            fresh.PowerBand.Value is not HealthBand band || !band.IsFivePercentCurveBand)
            gaps.Add("CurveManaBand");
        foreach(var baseSpell in new[] {1130,1978,3044,75})
        {
            if(ConditionEvaluator.SpellReady(fresh,baseSpell)!=Truth.True)
                gaps.Add("SpellReady:"+baseSpell);
            if(HunterSpellFamilies.Find(fresh,baseSpell,now).SelectedRank is null)
                gaps.Add("VerifiedRank:"+baseSpell);
        }
        if(fresh.TargetEpoch.Quality!=Knowledge.Known)
            gaps.Add("TargetEpoch");
        foreach(var baseSpell in new[] {1130,1978})
        {
            var family=HunterSpellFamilies.Ranks(baseSpell);
            if(fresh.TargetEpoch.Quality!=Knowledge.Known ||
               fresh.TargetEpoch.Value is not int epoch ||
               !family.All(id=>fresh.Auras.TryGetValue(
                    new AuraKey("target-epoch-"+epoch,id,true),out var aura) &&
                    aura.Present.Quality==Knowledge.Known))
                gaps.Add("TargetDebuffRanks:"+baseSpell);
        }
        return gaps.ToArray();
    }
}

internal sealed class HunterRotationAudit
{
    private readonly List<RotationAuditRow> rows=new();
    private readonly int capacity;
    private readonly TimeSpan window;
    private RotationProfileV2? profile;
    private IReadOnlyDictionary<string,int>? overrides;
    private DateTimeOffset lastCapture;
    private int orphanEvents;
    private int duplicateEvents;
    private int eventSameFamily;
    private int eventDifferentFamily;
    private string[] latestMissing=Array.Empty<string>();
    public HunterRotationAudit(int capacity=1500,TimeSpan? matchWindow=null)
    {
        if(capacity is <1 or >2000)throw new ArgumentOutOfRangeException(nameof(capacity));
        this.capacity=capacity;
        window=matchWindow??TimeSpan.FromMilliseconds(1200);
    }
    public IReadOnlyList<RotationAuditRow> Rows=>rows.ToArray();
    public void Clear()
    {
        rows.Clear();lastCapture=default;profile=null;overrides=null;
        orphanEvents=duplicateEvents=eventSameFamily=eventDifferentFamily=0;
        latestMissing=Array.Empty<string>();
    }
    public void RecordUncorrelatedEvent()=>orphanEvents++;
    public void RecordDuplicateEvent()=>duplicateEvents++;
    // One diagnostic snapshot per polling interval; do not fabricate an execution.
    public RotationAuditRow Capture(RotationProfileV2 rotation,GameState state,
        IReadOnlyDictionary<string,int>? settings,DateTimeOffset at)
    {
        var evaluation=RotationXmlV2.Evaluate(rotation,state,settings,at,rotation.Mode);
        latestMissing=HunterAuditReadiness.Missing(state,at);
        var trace=evaluation.Trace.Select(t=>t.RuleId+":"+t.Outcome+" "+t.Reason)
            .Take(20).Concat(rotation.Rules.Select(r=>{
                var rank=HunterSpellFamilies.Find(state,r.SpellId,at);
                return "Rank "+r.SpellId+"="+rank.Status+
                    (rank.SelectedRank is int id?" selected="+id:"");
            })).Take(32).ToArray();
        // A recommendation represents XML conditional assessment, not user input.
        var row=new RotationAuditRow(at,evaluation.Recommendation?.SpellId,
            evaluation.Recommendation?.RuleId,null,
            evaluation.Recommendation is null?RotationAuditVerdict.Blocked:
                RotationAuditVerdict.Unobservable,
            evaluation.Recommendation is null?
                (evaluation.BlockReason.Length==0?"UnknownRequiredSignals":evaluation.BlockReason):
                "NoVerifiedCastEvent",trace,
            state.TargetEpoch.Quality==Knowledge.Known?state.TargetEpoch.Value:null);
        Add(row);
        profile=rotation;
        overrides=settings is null?null:new Dictionary<string,int>(settings);
        lastCapture=at;
        return row;
    }
    // Can only match independently established combat-log successes.
    // No LGD state flip, mouse event, pending key press or inferred cooldown is proof.
    public RotationAuditRow? Observe(RotationObservedCast observed)
    {
        if(observed.Evidence is not (RotationCastEvidence.CombatLogSuccess or RotationCastEvidence.UnitSpellcastSucceeded) ||
           !observed.PlayerConfirmed ||
           observed.SpellId<=0 ||
           lastCapture==default || observed.At<lastCapture ||
           observed.At-lastCapture>window)return null;
        for(int i=rows.Count-1;i>=0;i--)
        {
            var row=rows[i];
            if(row.At>observed.At || observed.At-row.At>window || row.ObservedSpellId is not null)
                continue;
            // Do not correlate target-specific actions across changing targets.
            if(row.TargetEpoch is not null &&
                (observed.TargetEpoch is null || observed.TargetEpoch!=row.TargetEpoch))
                return null;
            // Compare family rank equivalents: 1130 vs 14323 is the same ability.
            int? expectedFamily=row.ExpectedSpellId is int e?HunterSpellFamilies.BaseId(e):null;
            int? actualFamily=HunterSpellFamilies.BaseId(observed.SpellId);
            var matched=row.ExpectedSpellId is int exp &&
                (exp==observed.SpellId ||
                 (expectedFamily is not null && expectedFamily==actualFamily));
            // Different cast during this window may be a manually triggered skill,
            // so "Mismatch" means observed != expected, NOT proven LazyG failure.
            if(observed.Evidence==RotationCastEvidence.UnitSpellcastSucceeded)
            {
                if(matched)eventSameFamily++;else eventDifferentFamily++;
            }
            var verdict=observed.Evidence==RotationCastEvidence.UnitSpellcastSucceeded
                ? RotationAuditVerdict.EventOnly
                : row.ExpectedSpellId is null?RotationAuditVerdict.Blocked:
                  matched?RotationAuditVerdict.Match:RotationAuditVerdict.Mismatch;
            var updated=row with { ObservedSpellId=observed.SpellId,Verdict=verdict,
                Reason=verdict switch {
                    RotationAuditVerdict.EventOnly=>matched
                        ?"PlayerSpellcastEventSameFamily;EffectUnverified"
                        :"PlayerSpellcastEventDifferentOrBlocked;EffectUnverified",
                    RotationAuditVerdict.Match=>"ObservedCastMatchesRuleFamily",
                    RotationAuditVerdict.Mismatch=>"ObservedDifferentCast;ActorAttributionUnproven",
                    _=>"CastObservedButRuleBlocked;ActorAttributionUnproven"
                }};
            rows[i]=updated;
            return updated;
        }
        return null;
    }
    private void Add(RotationAuditRow row)
    {
        if(rows.Count==capacity)rows.RemoveAt(0);
        rows.Add(row);
    }
    // Export only static rule IDs, bounded timestamps, spell ids, classified outcomes,
    // and quality traces. Never raw RGB, inputs, coordinates or player/target identity.
    public string ExportJson()
    {
        var items=rows.Select(r=>new {
            at=r.At.ToUniversalTime(),r.ExpectedSpellId,r.ExpectedRule,
            r.ObservedSpellId,Verdict=r.Verdict.ToString(),r.Reason,
            Conditions=r.Conditions
        }).ToArray();
        return JsonSerializer.Serialize(new {
            schema=1,client="forever",spec="hunter-beast-mastery",mode="PvE",
            note="Diagnostic only; absence of cast evidence is not an execution failure. No automatic input.",
            missingCapabilities=latestMissing,
            eventSummary=new {
                SameRuleFamily=eventSameFamily,
                DifferentOrBlocked=eventDifferentFamily,
                Uncorrelated=orphanEvents,
                Duplicate=duplicateEvents,
                Note="Events are not proof of impact or LazyG-originated input."
            },
            rows=items
        },new JsonSerializerOptions {WriteIndented=true});
    }
    public string Summary()
    {
        int matches=rows.Count(r=>r.Verdict==RotationAuditVerdict.Match);
        int mismatches=rows.Count(r=>r.Verdict==RotationAuditVerdict.Mismatch);
        int blocked=rows.Count(r=>r.Verdict==RotationAuditVerdict.Blocked);
        int events=rows.Count(r=>r.Verdict==RotationAuditVerdict.EventOnly);
        int unverified=rows.Count(r=>r.Verdict==RotationAuditVerdict.Unobservable);
        return "Hunter BM XML audit: "+rows.Count+" samples | observed matches="+matches+
            " | differences="+mismatches+" (attribution unproven) | player cast events="+events+
            " (effect unverified; same family="+eventSameFamily+
            ", different/blocked="+eventDifferentFamily+") | unmatched="+orphanEvents+
            " | duplicate="+duplicateEvents+" | rule blocked="+blocked+
            " | cast unobservable="+unverified+" | missing signals="+latestMissing.Length;
    }
}
