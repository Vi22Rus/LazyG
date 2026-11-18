using System;
using LazyG.Desktop.Engine;
var now=DateTimeOffset.UtcNow;
var empty=GameState.Empty(now);
Assert(empty.PlayerHealthPercent.Quality==Knowledge.Unknown);
Assert(ConditionEvaluator.GcdReady(empty)==Truth.Unknown);
Assert(ConditionEvaluator.SpellReady(empty,1130)==Truth.Unknown);
Assert(!ConditionEvaluator.CanRecommend(ConditionEvaluator.SpellReady(empty,1130)));
Assert(TruthLogic.And(Truth.False,Truth.Unknown)==Truth.False);
Assert(TruthLogic.And(Truth.True,Truth.Unknown)==Truth.Unknown);
Assert(TruthLogic.Or(Truth.Unknown,Truth.True)==Truth.True);
Assert(TruthLogic.Or(Truth.Unknown,Truth.False)==Truth.Unknown);
Assert(TruthLogic.Not(Truth.Unknown)==Truth.Unknown);
Assert(TruthLogic.AtLeast(2,Truth.True,Truth.Unknown)==Truth.Unknown);
Assert(TruthLogic.AtLeast(2,Truth.True,Truth.False)==Truth.False);
Assert(TruthLogic.AtLeast(2,Truth.True,Truth.True)==Truth.True);
var state=empty with {
    InCombat=Observed<bool>.Known(true,now),
    TargetExists=Observed<bool>.Known(true,now),
    TargetHostile=Observed<bool>.Known(true,now),
    TargetAlive=Observed<bool>.Known(true,now)
};
Assert(ConditionEvaluator.InCombat(state)==Truth.True);
Assert(ConditionEvaluator.HasTarget(state)==Truth.True);
Assert(ConditionEvaluator.TargetHostile(state)==Truth.True);
Assert(ConditionEvaluator.TargetBelow(state,20)==Truth.Unknown);
Assert(!ConditionEvaluator.CanRecommend(
    ConditionEvaluator.InCombat(state),
    ConditionEvaluator.TargetBelow(state,20)));
var stale=state.Age(now.AddSeconds(2),TimeSpan.FromMilliseconds(900));
Assert(stale.InCombat.Quality==Knowledge.Stale);
Assert(ConditionEvaluator.InCombat(stale)==Truth.Unknown);
var known=state with {
    PlayerHealthPercent=Observed<int>.Known(65,now),
    GcdRemainingMilliseconds=Observed<int>.Known(0,now)
};
Assert(ConditionEvaluator.HealthBelow(known,70)==Truth.True);
Assert(ConditionEvaluator.GcdReady(known)==Truth.True);
Assert(ConditionEvaluator.HealthBelow(known,30)==Truth.False);
Console.WriteLine("GameState tri-state / unknown / staleness / safe gates: PASS");
void Assert(bool ok){if(!ok)throw new Exception("GameState regression failed");}
