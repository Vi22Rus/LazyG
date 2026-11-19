using System;
using System.Collections.Generic;
using System.Linq;

namespace LazyG.Desktop.Engine;

// An IOCTL completion is not evidence that a debuff landed.
// For XML rules that REQUIRE a target debuff, never advance to unrelated
// abilities after a command merely because an aura became Unknown.
// This tracker never manufactures aura presence or GCD readiness.
internal enum DebuffConfirmationState
{
    Idle, AwaitingEvidence, StillAbsent, Confirmed, TargetChanged
}
internal sealed record DebuffConfirmationResult(
    DebuffConfirmationState State,string Detail,int? PendingSpellId=null);

internal sealed class DebuffConfirmationGate
{
    private sealed record Pending(string RuleId,int SpellId,int BaseSpellId,
        int TargetEpoch,DateTimeOffset SentAt);
    private Pending? pending;
    private DebuffConfirmationState current=DebuffConfirmationState.Idle;
    private const int MinRetryMilliseconds=900; // retry pacing ONLY; NOT a GCD
    public bool HasPending=>pending is not null;
    public void Reset() {pending=null;current=DebuffConfirmationState.Idle;}

    public static bool RequiresTargetDebuff(string? ruleId) =>
        ruleId is "markMissing" or "stingMissing";

    // Call ONLY after the Logitech tap returns without driver error.
    public bool MarkSent(RotationRecommendation recommendation,GameState state,
        DateTimeOffset at)
    {
        if(!RequiresTargetDebuff(recommendation.RuleId) ||
           state.Transport!=Knowledge.Known ||
           state.TargetExists.Is(x=>x)!=Truth.True ||
           state.TargetEpoch.Quality!=Knowledge.Known ||
           state.TargetEpoch.Value is not int epoch)
            return false;
        int? family=HunterSpellFamilies.BaseId(recommendation.SpellId);
        if(family is not (1130 or 1978))return false;
        pending=new Pending(recommendation.RuleId,recommendation.SpellId,
            family.Value,epoch,at);
        current=DebuffConfirmationState.AwaitingEvidence;
        return true;
    }

    private static (bool Confirmed,bool Complete) AuraEvidence(
        GameState state,int epoch,int baseSpellId)
    {
        var ranks=HunterSpellFamilies.Ranks(baseSpellId);
        if(ranks.Length==0)return (false,false);
        bool complete=true;
        foreach(int id in ranks)
        {
            var key=new AuraKey("target-epoch-"+epoch,id,true);
            if(!state.Auras.TryGetValue(key,out var aura) ||
               aura.Present.Quality!=Knowledge.Known)
            {
                complete=false;
                continue;
            }
            if(aura.Present.Value==true)return (true,true);
        }
        return (false,complete);
    }

    public DebuffConfirmationResult Observe(GameState state,DateTimeOffset at)
    {
        if(pending is not Pending p)
            return new(DebuffConfirmationState.Idle,"No target debuff awaiting confirmation");
        // Missing or stale frames cannot positively clear pending state.
        var fresh=state.Age(at,TimeSpan.FromMilliseconds(900));
        if(fresh.Transport!=Knowledge.Known ||
           fresh.TargetEpoch.Quality!=Knowledge.Known ||
           fresh.TargetEpoch.Value is not int epoch ||
           fresh.TargetExists.Is(x=>x)!=Truth.True)
        {
            current=DebuffConfirmationState.AwaitingEvidence;
            return new(current,"Awaiting fresh target/aura telemetry",p.SpellId);
        }
        if(epoch!=p.TargetEpoch)
        {
            Reset();
            return new(DebuffConfirmationState.TargetChanged,
                "Target epoch changed; previous debuff cannot authorize next target");
        }
        var evidence=AuraEvidence(fresh,epoch,p.BaseSpellId);
        if(evidence.Confirmed)
        {
            Reset();
            return new(DebuffConfirmationState.Confirmed,
                "Aura observed present on same target (not inferred from keypress)");
        }
        current=evidence.Complete?
            DebuffConfirmationState.StillAbsent:
            DebuffConfirmationState.AwaitingEvidence;
        return new(current,evidence.Complete?
            "Same target: all aura ranks confirmed absent; eligible for real-GCD-gated retry":
            "Same target: debuff presence Unknown; do not advance rotation",
            p.SpellId);
    }

    public bool MaySend(RotationRecommendation candidate,GameState state,
        DateTimeOffset at,out string reason)
    {
        reason="NO DEBUFF PENDING";
        if(pending is not Pending p)return true;
        var observation=Observe(state,at);
        if(observation.State is DebuffConfirmationState.Confirmed or
            DebuffConfirmationState.TargetChanged)return true;
        if(observation.State!=DebuffConfirmationState.StillAbsent)
        {
            reason="DEBUFF UNCONFIRMED: "+p.RuleId+" / "+observation.Detail;
            return false;
        }
        if(candidate.SpellId!=p.SpellId || candidate.RuleId!=p.RuleId)
        {
            reason="WAITING FOR DEBUFF RETRY: "+p.RuleId+
                " still absent; unrelated spell blocked";
            return false;
        }
        // Real GCD and spell readiness are still verified by XML/command path.
        // This small delay prevents 400ms feedback frames from spamming taps.
        if(at-p.SentAt<TimeSpan.FromMilliseconds(MinRetryMilliseconds))
        {
            reason="DEBUFF RETRY PACING: "+p.RuleId;
            return false;
        }
        reason="DEBUFF STILL ABSENT: retry same spell with existing XML/GCD gates";
        return true;
    }
}
