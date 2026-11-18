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

// Independent v1 diagnostic packet: version, sequence, spell id, four quality codes.
var probeBytes=new byte[] {
    0x4C,0x47,0x44,1,7,0,0,4,106,2,2,0,0,0,0,0xA5,0,0
}; // SpellID 1130
int checksum=0;
for(int i=0;i<15;i++)checksum=(checksum+probeBytes[i])&255;
probeBytes[16]=(byte)checksum;
probeBytes[17]=(byte)(255-checksum);
Assert(ForeverSpellProbeCodec.TryDecode(probeBytes,out var spellProbe));
Assert(spellProbe!.SpellId==1130);
var spellObserved=ForeverSpellProbeCodec.ToSpellState(spellProbe,now);
Assert(spellObserved.Learned.Is(x=>x)==Truth.True);
Assert(spellObserved.Usable.Is(x=>x)==Truth.True);
Assert(spellObserved.CooldownMs.Quality==Knowledge.Unknown);
Assert(!ConditionEvaluator.CanRecommend(
    (empty with { Spells=new System.Collections.Generic.Dictionary<int,SpellState>
    { [1130]=spellObserved } }).Spells[1130].CooldownMs.Is(x=>x==0)));
probeBytes[10]=3;
Assert(!ForeverSpellProbeCodec.TryDecode(probeBytes,out _)); // CRC failure
probeBytes[10]=2;
probeBytes[9]=7;
checksum=0;
for(int i=0;i<15;i++)checksum=(checksum+probeBytes[i])&255;
probeBytes[16]=(byte)checksum;
probeBytes[17]=(byte)(255-checksum);
Assert(!ForeverSpellProbeCodec.TryDecode(probeBytes,out _)); // invalid status

Console.WriteLine("GameState and isolated SpellProbe v1 regression: PASS");
void Assert(bool ok){if(!ok)throw new Exception("GameState regression failed");}
