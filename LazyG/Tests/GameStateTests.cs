using System;
using LazyG.Desktop.Engine;
using LazyG.Desktop.Diagnostics;
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
var baseline=empty with {
    Client="forever",Transport=Knowledge.Known,
    ClassId=Observed<int>.Known(3,now)
};
var accepted=ForeverSpellProbeCodec.ApplyDiagnostic(baseline,spellProbe!,now,now,
    TimeSpan.FromSeconds(1));
Assert(accepted.Spells.ContainsKey(1130));
Assert(ConditionEvaluator.SpellReady(accepted,1130)==Truth.Unknown);
var expired=ForeverSpellProbeCodec.ApplyDiagnostic(baseline,spellProbe!,
    now.AddSeconds(-3),now,TimeSpan.FromSeconds(1));
Assert(!expired.Spells.ContainsKey(1130));
Assert(!ForeverSpellProbeCodec.ApplyDiagnostic(empty,spellProbe!,now,now,
    TimeSpan.FromSeconds(1)).Spells.ContainsKey(1130));
probeBytes[10]=3;
Assert(!ForeverSpellProbeCodec.TryDecode(probeBytes,out _)); // CRC failure
probeBytes[10]=2;
probeBytes[9]=7;
checksum=0;
for(int i=0;i<15;i++)checksum=(checksum+probeBytes[i])&255;
probeBytes[16]=(byte)checksum;
probeBytes[17]=(byte)(255-checksum);
Assert(!ForeverSpellProbeCodec.TryDecode(probeBytes,out _)); // invalid status


// Target epoch and event hints; a UNIT_AURA notification is never proof
// that any specific buff/debuff exists.
var timeBased=baseline with {
    Spells=new System.Collections.Generic.Dictionary<int,SpellState> {
        [1130]=new SpellState(Observed<bool>.Known(true,now),
            Observed<bool>.Known(true,now),Observed<bool>.Missing(),
            Observed<int>.Known(0,now),Observed<int>.Missing())
    },
    Auras=new System.Collections.Generic.Dictionary<AuraKey,AuraState> {
        [new AuraKey("target-epoch-0",1130,true)]=new AuraState(
            Observed<bool>.Known(true,now),Observed<int>.Known(1,now),
            Observed<int>.Missing())
    }
};
Assert(ConditionEvaluator.SpellReady(timeBased,1130)==Truth.True);
var timeExpired=timeBased.Age(now.AddSeconds(4),TimeSpan.FromSeconds(2));
Assert(timeExpired.Spells[1130].CooldownMs.Quality==Knowledge.Stale);
Assert(timeExpired.Auras[new AuraKey("target-epoch-0",1130,true)]
    .Present.Quality==Knowledge.Stale);
Assert(ConditionEvaluator.SpellReady(timeExpired,1130)==Truth.Unknown);
Assert(ConditionEvaluator.HasAura(timeExpired,
    new AuraKey("target-epoch-0",1130,true))==Truth.Unknown);
var tracker=new ForeverCombatTracker();
Assert(tracker.Apply(new ForeverCombatEvent(
    ForeverCombatEventKind.TargetCastStarted,now,12345)));
var cast=tracker.Snapshot(now,TimeSpan.FromSeconds(2));
Assert(cast.TargetCasting.Is(x=>x)==Truth.True);
Assert(cast.TargetCastSpellId.Value==12345);
Assert(tracker.Apply(new ForeverCombatEvent(
    ForeverCombatEventKind.TargetAuraChanged,now.AddMilliseconds(100))));
Assert(tracker.Snapshot(now.AddMilliseconds(100),TimeSpan.FromSeconds(2))
    .TargetAuraChangedAt.HasValue);
Assert(tracker.Apply(new ForeverCombatEvent(
    ForeverCombatEventKind.TargetChanged,now.AddMilliseconds(200))));
var changed=tracker.Snapshot(now.AddMilliseconds(200),TimeSpan.FromSeconds(2));
Assert(changed.TargetEpoch==1);
Assert(changed.TargetCasting.Quality==Knowledge.Unknown);
Assert(changed.TargetCastSpellId.Quality==Knowledge.Unknown);
Assert(changed.TargetAuraChangedAt is null);
Assert(!tracker.Apply(new ForeverCombatEvent(
    ForeverCombatEventKind.TargetCastStarted,now.AddMilliseconds(100),12345)));
Assert(tracker.Apply(new ForeverCombatEvent(
    ForeverCombatEventKind.TargetCastStarted,now.AddMilliseconds(300))));
Assert(tracker.Snapshot(now.AddMilliseconds(300),TimeSpan.FromSeconds(2))
    .TargetCastSpellId.Quality==Knowledge.Unknown);
Assert(tracker.Apply(new ForeverCombatEvent(
    ForeverCombatEventKind.TargetCastStopped,now.AddMilliseconds(400))));
Assert(tracker.Snapshot(now.AddMilliseconds(400),TimeSpan.FromSeconds(2))
    .TargetCasting.Is(x=>x)==Truth.False);
Assert(tracker.Apply(new ForeverCombatEvent(
    ForeverCombatEventKind.PlayerCastSucceeded,now.AddMilliseconds(500),1130)));
var afterSuccess=tracker.Snapshot(now.AddMilliseconds(500),TimeSpan.FromSeconds(2));
Assert(afterSuccess.PlayerLastSucceededSpellId.Value==1130);
Assert(tracker.Snapshot(now.AddSeconds(4),TimeSpan.FromSeconds(2))
    .PlayerLastSucceededSpellId.Quality==Knowledge.Stale);
Assert(!tracker.Snapshot(now.AddSeconds(4),TimeSpan.FromSeconds(2))
    .PlayerLastSucceededAt.HasValue);


// Safety regression: 0-4% is not evidence of life or exactly zero HP.
Assert(HealthBand.TryParse("0–4%",out var nearZero));
Assert(nearZero.Lower==0 && nearZero.Upper==4);
Assert(!HealthBand.TryParse("unavailable",out _));
Assert(!HealthBand.TryParse("4–0%",out _));
Assert(ConditionEvaluator.TargetBelowBand(
    Observed<HealthBand>.Known(nearZero,now),5)==Truth.True);
Assert(ConditionEvaluator.TargetBelowBand(
    Observed<HealthBand>.Known(nearZero,now),4)==Truth.False);
Assert(ConditionEvaluator.TargetBelowBand(Observed<HealthBand>.Missing(),5)==Truth.Unknown);
Assert(ConditionEvaluator.TargetBelowBand(
    Observed<HealthBand>.Known(new HealthBand(9,0),now),5)==Truth.Unknown);
Assert(TargetLifeDecoder.Alive(true,false,false,now).Quality==Knowledge.Unknown);
Assert(TargetLifeDecoder.Alive(true,false,true,now).Is(x=>x)==Truth.False);
Assert(TargetLifeDecoder.Alive(true,true,false,now).Is(x=>x)==Truth.True);
Assert(TargetLifeDecoder.Alive(true,true,true,now).Quality==Knowledge.Unknown);
Assert(TargetLifeDecoder.Alive(false,false,false,now).Quality==Knowledge.Unknown);
var attackBase=timeBased with {
    Transport=Knowledge.Known,
    TargetExists=Observed<bool>.Known(true,now),
    TargetHostile=Observed<bool>.Known(true,now),
    TargetAlive=Observed<bool>.Known(true,now)
};
var band04=Observed<HealthBand>.Known(nearZero,now);
Assert(ConditionEvaluator.AttackTarget(attackBase)==Truth.True);
Assert(ConditionEvaluator.CanRecommendExecute(attackBase,1130,band04,20));
var corpse=attackBase with {TargetAlive=Observed<bool>.Known(false,now)};
Assert(ConditionEvaluator.AttackTarget(corpse)==Truth.False);
Assert(!ConditionEvaluator.CanRecommendExecute(corpse,1130,band04,20));
Assert(!ConditionEvaluator.CanRecommendTargetedAttack(corpse,1130));
var absent=attackBase with {TargetExists=Observed<bool>.Known(false,now)};
Assert(!ConditionEvaluator.CanRecommendExecute(absent,1130,band04,20));
var uncertain=attackBase with {TargetAlive=Observed<bool>.Missing()};
Assert(!ConditionEvaluator.CanRecommendExecute(uncertain,1130,band04,20));
var notHostile=attackBase with {TargetHostile=Observed<bool>.Missing()};
Assert(!ConditionEvaluator.CanRecommendTargetedAttack(notHostile,1130));
var untrusted=attackBase with {Transport=Knowledge.Stale};
Assert(!ConditionEvaluator.CanRecommendTargetedAttack(untrusted,1130));
Assert(!ConditionEvaluator.CanRecommendExecute(attackBase,1130,
    band04,4)); // 0-4 not necessarily below 4
Assert(!ConditionEvaluator.CanRecommendExecute(attackBase,1130,
    Observed<HealthBand>.Missing(),20));


// XML dispatch boundary: ALL rules, not only Execute, must pass living hostile
// target + fresh transport + known SpellReady + known GCD.
var sampleXml="<Rotation client=\"forever\" version=\"1\">"+
    "<Rule priority=\"1\" spellId=\"1130\" kind=\"Execute\" targetHpBelow=\"20\"/>"+
    "<Rule priority=\"2\" spellId=\"1130\" kind=\"Attack\"/>"+
    "</Rotation>";
var parsed=XmlRotationDispatcher.Parse(sampleXml);
var ready=attackBase with {GcdRemainingMilliseconds=Observed<int>.Known(0,now)};
var recommendation=XmlRotationDispatcher.Evaluate(parsed,ready,band04,now);
Assert(recommendation?.Kind==XmlActionKind.Execute);
Assert(recommendation?.Priority==1);
Assert(XmlRotationDispatcher.Evaluate(parsed,corpse with {
    GcdRemainingMilliseconds=Observed<int>.Known(0,now)},band04,now) is null);
Assert(XmlRotationDispatcher.Evaluate(parsed,absent with {
    GcdRemainingMilliseconds=Observed<int>.Known(0,now)},band04,now) is null);
Assert(XmlRotationDispatcher.Evaluate(parsed,uncertain with {
    GcdRemainingMilliseconds=Observed<int>.Known(0,now)},band04,now) is null);
Assert(XmlRotationDispatcher.Evaluate(parsed,notHostile with {
    GcdRemainingMilliseconds=Observed<int>.Known(0,now)},band04,now) is null);
Assert(XmlRotationDispatcher.Evaluate(parsed,attackBase,band04,now) is null); // GCD missing
Assert(XmlRotationDispatcher.Evaluate(parsed,ready with {
    GcdRemainingMilliseconds=Observed<int>.Known(850,now)},band04,now) is null);
Assert(XmlRotationDispatcher.Evaluate(parsed,ready,band04,now.AddSeconds(2)) is null);
Assert(XmlRotationDispatcher.Evaluate(parsed,ready,Observed<HealthBand>.Missing(),now)
    ?.Kind==XmlActionKind.Attack); // non-execute still under global target gate
var executeOnly=XmlRotationDispatcher.Parse(
    "<Rotation client=\"forever\" version=\"1\">"+
    "<Rule priority=\"1\" spellId=\"1130\" kind=\"Execute\" targetHpBelow=\"20\"/>"+
    "</Rotation>");
Assert(XmlRotationDispatcher.Evaluate(executeOnly,ready,
    Observed<HealthBand>.Missing(),now) is null);
Assert(XmlRotationDispatcher.Evaluate(executeOnly,ready,
    Observed<HealthBand>.Known(new HealthBand(20,24),now),now) is null);
Assert(XmlRotationDispatcher.Evaluate(parsed,ready with {
    Spells=new System.Collections.Generic.Dictionary<int,SpellState>()},band04,now) is null);
Assert(XmlRotationDispatcher.Evaluate(parsed,ready with {
    Transport=Knowledge.Unknown},band04,now) is null);
Assert(XmlRotationDispatcher.Evaluate(parsed,ready with {
    TargetAlive=Observed<bool>.Known(false,now)},band04,now) is null);
Assert(XmlRotationDispatcher.Evaluate(parsed,ready with {
    TargetExists=Observed<bool>.Missing()},band04,now) is null);
Assert(XmlRotationDispatcher.Evaluate(parsed,ready with {
    TargetHostile=Observed<bool>.Missing()},band04,now) is null);
Assert(XmlRotationDispatcher.Evaluate(parsed,ready with {
    GcdRemainingMilliseconds=Observed<int>.Missing(Knowledge.Protected)},band04,now) is null);
Assert(XmlRotationDispatcher.Evaluate(parsed,ready,band04,now.AddMilliseconds(-1)) is null);
void BadXml(string xml)
{
    try { XmlRotationDispatcher.Parse(xml);throw new Exception("Unsafe XML accepted"); }
    catch(FormatException) {}
}
BadXml("<!DOCTYPE Rotation [<!ENTITY x SYSTEM 'file:///secret'>]><Rotation client=\"forever\" version=\"1\"><Rule priority=\"1\" spellId=\"1130\" kind=\"Attack\"/></Rotation>");
BadXml("<Rotation client=\"3.3.5\" version=\"1\"><Rule priority=\"1\" spellId=\"1130\" kind=\"Attack\"/></Rotation>");
BadXml("<Rotation client=\"forever\" version=\"1\"><Rule priority=\"1\" spellId=\"1130\" kind=\"Heal\"/></Rotation>");
BadXml("<Rotation client=\"forever\" version=\"1\"><Rule priority=\"1\" spellId=\"1130\" kind=\"Attack\" targetHpBelow=\"20\"/></Rotation>");
BadXml("<Rotation client=\"forever\" version=\"1\"><Rule priority=\"1\" spellId=\"1130\" kind=\"Execute\"/></Rotation>");
BadXml("<Rotation client=\"forever\" version=\"1\"><Rule priority=\"1\" spellId=\"1130\" kind=\"Attack\"/><Rule priority=\"1\" spellId=\"44\" kind=\"Attack\"/></Rotation>");
BadXml("<Rotation client=\"forever\" version=\"1\"><Rule priority=\"1\" spellId=\"0\" kind=\"Attack\"/></Rotation>");


// A read-only UI description cannot change the centralized XML action gate.
Assert(XmlRotationPreview.Describe(parsed,corpse with {
    GcdRemainingMilliseconds=Observed<int>.Known(0,now)},band04,now).Contains("target"));
Assert(XmlRotationPreview.Describe(parsed,ready,band04,now).Contains("suggestion ONLY"));
Assert(XmlRotationPreview.Describe(parsed,attackBase,band04,now).Contains("GCD"));
Assert(XmlRotationPreview.Describe(parsed,ready,band04,now.AddSeconds(2))
    .Contains("stale"));
Assert(XmlRotationPreview.Describe(null,ready,band04,now).Contains("no validated profile"));

Console.WriteLine("GameState, corpse safety, XML dispatch and preview regression: PASS");
void Assert(bool ok){if(!ok)throw new Exception("GameState regression failed");}
