using System;
using System.Collections.Generic;

namespace LazyG.Desktop.Engine;

// XML recommendation session: evaluates current GameState only.
// Logitech input is controlled separately by the MainWindow Start/Stop gate.
// No recommendation survives disconnect, missing data, or elapsed TTL.
internal sealed class RotationPreviewSession
{
    private RotationProfileV2? profile;
    private IReadOnlyDictionary<string,int>? overrides;
    public bool Running => profile is not null;
    public RotationRecommendation? Current { get; private set; }
    public string Status { get; private set; } = "STOPPED";
    public string? RuleId => Current?.RuleId;
    public int? SettingValue(string key) =>
        overrides is not null && overrides.TryGetValue(key,out int value) ? value : null;
    public bool IsSettingEnabled(string key) => profile is not null &&
        overrides is not null && overrides.TryGetValue(key,out int value) && value==1;
    public void Start(RotationProfileV2 next,IReadOnlyDictionary<string,int> settings)
    {
        if(next.Client!="forever" || next.ClassId!=3 || next.SpecIndex!=1 ||
            next.Mode!="PvE")
            throw new InvalidOperationException("Only Hunter BM PvE read-only preview is supported");
        if(next.Rules.Count==0)throw new InvalidOperationException("Empty XML rotation");
        RotationXmlV2.Resolve(next,settings);
        // Load resolved values, not only JSON overrides. Otherwise all XML
        // default-on settings appear disabled in diagnostic comparisons.
        overrides=RotationXmlV2.Resolve(next,settings);
        profile=next;
        Current=null;
        Status="AWAITING GAME DATA · XML ROTATION";
    }
    public void Stop(string reason="STOPPED")
    {
        profile=null;overrides=null;Current=null;Status=reason;
    }
    public RotationRecommendation? Update(GameState state,DateTimeOffset at)
    {
        if(profile is null)return null;
        // Need a positively validated live snapshot: no cached old recommendation.
        if(state.Transport!=Knowledge.Known ||
           state.CapturedAt>at ||
           at-state.CapturedAt>TimeSpan.FromMilliseconds(900))
        {
            Current=null;Status="WAITING FOR FRESH RGB";
            return null;
        }
        var evaluation=RotationXmlV2.Evaluate(profile,state,overrides,at,profile.Mode);
        Current=evaluation.Recommendation;
        Status=Current is null
            ? "WAITING · "+(evaluation.BlockReason.Length==0?
                "NO ELIGIBLE RULE":evaluation.BlockReason)
            : "RECOMMENDING SPELL "+Current.SpellId+" · DEV";
        return Current;
    }
}
