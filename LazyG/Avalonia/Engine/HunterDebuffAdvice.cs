using System;

namespace LazyG.Desktop.Engine;

// Sonah-inspired "debuff missing" recommendation for the display layer only.
// Sonah keeps recommending when no successful cast / aura proves completion.
// LazyG intentionally does not infer a successful cast from an HID report.
// Only the strict XML evaluator may authorize a G Hub command.
internal sealed record HunterDisplayAdvice(int SpellId,string RuleId,string Reason);
internal static class HunterDebuffAdvice
{
    public static HunterDisplayAdvice? SuggestMark(GameState game,DateTimeOffset at,
        bool markEnabled)
    {
        if(!markEnabled)return null;
        var state=game.Age(at,TimeSpan.FromMilliseconds(900));
        if(state.Transport!=Knowledge.Known ||
           state.ClassId.Is(x=>x==3)!=Truth.True ||
           state.SpecIndex.Is(x=>x==1)!=Truth.True ||
           ConditionEvaluator.AttackTarget(state)!=Truth.True ||
           state.TargetEpoch.Quality!=Knowledge.Known ||
           state.TargetEpoch.Value is not int epoch)return null;
        int[] ranks=HunterSpellFamilies.Ranks(1130);
        if(ranks.Length==0)return null;
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
            if(aura.Present.Value==true)return null;
        }
        // A WoW player-successful cast may temporarily stand in for a
        // hidden aura, as Sonah's SinceCast fallback does. This only affects
        // the advisory icon, never proves a debuff landed or authorizes HID.
        if(!complete &&
           state.TargetDebuffCastHints.TryGetValue(1130,out var castHint) &&
           castHint.Is(v=>v)==Truth.True)
            return null;
        var rank=HunterSpellFamilies.Find(state,1130,at);
        if(rank.SelectedRank is not int selected)return null;
        return new HunterDisplayAdvice(selected,"markMissing",
            complete?"Hunter's Mark absent on current target":
                     "Hunter's Mark not confirmed (aura unknown); advisory only");
    }
}
