using System;
using System.Collections.Generic;
using System.Linq;

namespace LazyG.Desktop.Engine;

internal sealed record HunterPlannedKey(int BaseSpellId,int LearnedSpellId,int VirtualKey,
    string RuleId,DateTimeOffset At);

// Explicitly armed only, no actions from an incomplete or old observation.
// No guessed rank, no guessed GCD, no guessed debuff state or target epoch.
internal static class HunterExecutionGate
{
    public static HunterPlannedKey? Decide(RotationProfileV2? profile,GameState state,
        IReadOnlyDictionary<string,int>? settings,IReadOnlyDictionary<int,int> keyBindings,
        bool armed,bool foreground,DateTimeOffset now)
    {
        if(!armed || !foreground || profile is null ||
           profile.Client!="forever" || profile.ClassId!=3 || profile.SpecIndex!=1 ||
           profile.Mode!="PvE" || state.Client!="forever" ||
           state.CapturedAt>now || now-state.CapturedAt>TimeSpan.FromMilliseconds(500) ||
           state.TargetEpoch.Quality!=Knowledge.Known ||
           ConditionEvaluator.AttackTarget(state.Age(now,TimeSpan.FromMilliseconds(500)))!=Truth.True ||
           ConditionEvaluator.GcdReady(state.Age(now,TimeSpan.FromMilliseconds(500)))!=Truth.True)
            return null;

        var spells=new Dictionary<int,SpellState>(state.Spells);
        var resolved=new Dictionary<int,int>();
        foreach(var rule in profile.Rules)
        {
            if(!keyBindings.TryGetValue(rule.SpellId,out int vk) || !ValidKey(vk))
                return null;
            var finding=HunterSpellFamilies.Find(state,rule.SpellId,now);
            // Without complete knowledge of the learned rank family, a
            // lower-priority fallback may be unsafe: block the entire cycle.
            if(finding.SelectedRank is not int id ||
               !state.Spells.TryGetValue(id,out var selected))
                return null;
            // Retain only confirmed concrete-rank readiness; a spell on CD
            // becomes ineligible but does not block another proven rule.
            spells.Remove(rule.SpellId);
            if(ConditionEvaluator.SpellReady(state.Age(now,TimeSpan.FromMilliseconds(500)),id)
               ==Truth.True)
            {
                spells[rule.SpellId]=selected;
                resolved[rule.SpellId]=id;
            }
        }
        var projected=state with { Spells=spells };
        var outcome=RotationXmlV2.Evaluate(profile,projected,settings,now,"PvE").Recommendation;
        if(outcome is null || !resolved.TryGetValue(outcome.SpellId,out int learnedId) ||
           !keyBindings.TryGetValue(outcome.SpellId,out int binding) ||
           !ValidKey(binding))
            return null;
        return new HunterPlannedKey(outcome.SpellId,learnedId,binding,outcome.RuleId,now);
    }

    // F1..F12 only. No modifier keys, system shortcuts, text or unbound slots.
    public static bool ValidKey(int vk)=>vk is >=0x70 and <=0x7B;
}
