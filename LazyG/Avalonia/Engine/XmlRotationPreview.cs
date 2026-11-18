using System;

namespace LazyG.Desktop.Engine;

// Diagnostics-only explanation. Never authorizes a cast, and never bypasses
// the independent gates in XmlRotationDispatcher.Evaluate.
internal static class XmlRotationPreview
{
    public static string Describe(XmlRotationProfile? profile,GameState state,
        Observed<HealthBand> targetBand,DateTimeOffset now)
    {
        if(profile is null)return "XML preview: no validated profile.";
        if(profile.Client!="forever" || state.Client!="forever")
            return "XML preview: blocked (client mismatch).";
        if(state.CapturedAt>now || now-state.CapturedAt>TimeSpan.FromMilliseconds(900))
            return "XML preview: blocked (snapshot stale/invalid).";
        var snapshot=state.Age(now,TimeSpan.FromMilliseconds(900));
        var targetGate=ConditionEvaluator.AttackTarget(snapshot);
        if(targetGate!=Truth.True)
            return "XML preview: blocked (target exists/hostile/alive gate="+targetGate+").";
        var gcd=ConditionEvaluator.GcdReady(snapshot);
        if(gcd!=Truth.True)
            return "XML preview: blocked (GCD="+gcd+").";
        var band=targetBand.At(now,TimeSpan.FromMilliseconds(900));
        var selection=XmlRotationDispatcher.Evaluate(profile,snapshot,band,now);
        if(selection is not null)
            return "XML preview: suggestion ONLY, no inputs; SpellID "+
                selection.SpellId+" priority "+selection.Priority+
                " kind "+selection.Kind+".";
        return "XML preview: no eligible rule (SpellReady/cooldown or HP band Unknown/not satisfied).";
    }
}
