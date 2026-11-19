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

// LGC v1, separately encoded from LGD and RGB v2/v3: strict checksum,
 // reserved bytes, state quality and temporal fail-closed reporting.
var lgc=new byte[]{0x4c,0x47,0x43,1,7,0,0,53,227,2,1,1,0,0,0,0xa5,0,0};
int lgcSum=0;
for(int i=0;i<15;i++)lgcSum=(lgcSum+lgc[i])&255;
lgc[16]=(byte)lgcSum;lgc[17]=(byte)(255-lgcSum);
Assert(ForeverCooldownRgbCodec.TryDecode(lgc,out var cdPacket));
Assert(cdPacket is not null && cdPacket.SpellId==13795 &&
    cdPacket.SpellActive==ProbeCode.True &&
    cdPacket.SpellOnGcd==ProbeCode.False &&
    cdPacket.Gcd29515Active==ProbeCode.False &&
    cdPacket.Gcd29515OnGcd==ProbeCode.Unknown);
Assert(ForeverCooldownRgbCodec.Describe(cdPacket,now,now,
    TimeSpan.FromMilliseconds(900),true).Contains("GCD(29515)=False"));
Assert(ForeverCooldownRgbCodec.Describe(cdPacket,now,now.AddSeconds(2),
    TimeSpan.FromMilliseconds(900),true)=="LGC STALE");
Assert(ForeverCooldownRgbCodec.Describe(cdPacket,now,now,
    TimeSpan.FromMilliseconds(900),false).Contains("No verified"));
Assert(ForeverCooldownRgbCodec.Describe(null,now,now,
    TimeSpan.FromMilliseconds(900),true).Contains("absent"));
Assert(attackBase.GcdRemainingMilliseconds.Quality==Knowledge.Unknown);
var damaged=(byte[])lgc.Clone();
damaged[11]=2;
Assert(!ForeverCooldownRgbCodec.TryDecode(damaged,out _));
damaged=(byte[])lgc.Clone();
damaged[3]=2;
Assert(!ForeverCooldownRgbCodec.TryDecode(damaged,out _));
damaged=(byte[])lgc.Clone();
damaged[13]=1;
Assert(!ForeverCooldownRgbCodec.TryDecode(damaged,out _));
damaged=(byte[])lgc.Clone();
damaged[12]=5;
Assert(!ForeverCooldownRgbCodec.TryDecode(damaged,out _));
damaged=(byte[])lgc.Clone();
damaged[0]=0x44; // LGD is NOT LGC
Assert(!ForeverCooldownRgbCodec.TryDecode(damaged,out _));

// 0.2.19-dev: LGC freshness is independent from GameState readiness gates.
var lgcObserver=new ForeverCooldownObserver();
Assert(lgcObserver.Snapshot.Transport==Knowledge.Unknown);
var firstLgc=new CooldownRgbPacket(10,13795,ProbeCode.True,
    ProbeCode.False,ProbeCode.False,ProbeCode.Unknown);
var observed=lgcObserver.Update(true,firstLgc,now);
Assert(observed.Transport==Knowledge.Known &&
    observed.SpellCooldownActive.Is(x=>x)==Truth.True &&
    observed.Gcd29515Active.Is(x=>!x)==Truth.True &&
    observed.Gcd29515OnGcd.Quality==Knowledge.Unknown);
Assert(observed.LastNewFrameAt==now);
// Identical sequence does not refresh the timestamp, even when polled repeatedly.
var unchanged=lgcObserver.Update(true,firstLgc,now.AddMilliseconds(600));
Assert(unchanged.LastNewFrameAt==now && unchanged.Transport==Knowledge.Known);
var frozen=lgcObserver.Update(true,firstLgc,now.AddMilliseconds(1201));
Assert(lgcObserver.LastLossReason=="FrozenLgcSequence");
Assert(frozen.Transport==Knowledge.Stale &&
    frozen.SpellCooldownActive.Quality==Knowledge.Stale &&
    frozen.Gcd29515Active.Quality==Knowledge.Stale &&
    lgcObserver.Describe().Contains("STALE"));
// A new counter with an unknown or protected quality keeps Unknown or Protected.
var resumed=new CooldownRgbPacket(11,13795,ProbeCode.Protected,
    ProbeCode.Unknown,ProbeCode.True,ProbeCode.Protected);
var resumedAt=now.AddMilliseconds(1400);
var live=lgcObserver.Update(true,resumed,resumedAt);
Assert(lgcObserver.Recoveries==1 && lgcObserver.Describe().Contains("recoveries=1"));
Assert(live.SpellCooldownActive.Quality==Knowledge.Protected &&
    live.SpellOnGcd.Quality==Knowledge.Unknown &&
    live.Gcd29515Active.Is(x=>x)==Truth.True &&
    live.Gcd29515OnGcd.Quality==Knowledge.Protected);
// Corrupted same-counter content cannot be silently treated as a new frame.
var conflicting=resumed with { Gcd29515Active=ProbeCode.False };
Assert(lgcObserver.Recoveries==1);
Assert(lgcObserver.Update(true,conflicting,resumedAt.AddMilliseconds(100))
    .Transport==Knowledge.Unknown);
Assert(lgcObserver.Update(true,resumed,resumedAt.AddMilliseconds(200))
    .Transport==Knowledge.Known);
Assert(lgcObserver.Recoveries==2);
Assert(lgcObserver.LastLossReason=="SameSequenceConflict");
// Foreground loss clears the former 'Known False' immediately.
Assert(lgcObserver.Update(false,resumed,resumedAt.AddMilliseconds(250))
    .Transport==Knowledge.Unknown);
Assert(lgcObserver.Snapshot.Gcd29515Active.Quality==Knowledge.Unknown);
Assert(lgcObserver.LastLossReason=="BaseRgbIdentityLost");
Assert(lgcObserver.Update(true,firstLgc,resumedAt.AddMilliseconds(400))
    .Transport==Knowledge.Known);
Assert(lgcObserver.Recoveries==3);
Assert(lgcObserver.Update(true,null,resumedAt.AddMilliseconds(410))
    .Transport==Knowledge.Unknown);
Assert(lgcObserver.LastLossReason=="LgcPacketMissing");
Assert(lgcObserver.Update(true,firstLgc,resumedAt.AddMilliseconds(420))
    .Transport==Knowledge.Known);
Assert(lgcObserver.Recoveries==4);
Assert(lgcObserver.Update(true,firstLgc,resumedAt.AddMilliseconds(100))
    .Transport==Knowledge.Unknown); // clock rollback
Assert(lgcObserver.LastLossReason=="CaptureClockReversed");
lgcObserver.Reset();
Assert(lgcObserver.Snapshot.Transport==Knowledge.Unknown);
Assert(lgcObserver.Recoveries==0);
// No diagnostic outcome is a measured duration or a cast permission.
Assert(attackBase.GcdRemainingMilliseconds.Quality==Knowledge.Unknown);
Assert(ConditionEvaluator.GcdReady(attackBase)==Truth.Unknown);
Assert(XmlRotationDispatcher.Evaluate(parsed,attackBase,band04,now) is null);


// Unified RGB transport diagnostic (0.3.0-dev): v2, v3, Curve,
// optional LGD/LGC freshness, recoveries, errors and redacted report.
// All data here is synthetic; this does not authorize game input.
var rgbs=new RgbTransportMonitor();
var s0=now.AddSeconds(10);
RgbSample sample(DateTimeOffset at,byte? v3,byte? lgc,bool baseOk=true,
    bool foreground=true,bool lgdOn=false,byte? lgd=null,bool curve=true)
    => new(at,3.5,foreground,baseOk,v3.HasValue,v3,
        curve,lgdOn,lgd.HasValue,lgd,true,lgc.HasValue,lgc,
        foreground?"OK":"WindowOrCaptureUnavailable");
rgbs.Accept(sample(s0,44,10));
rgbs.SetDecoded(new RgbDecodedView(
    3,2,80,1,9,0x4c47,255,255,123,2,1,
    "80–84%","35–39%","95–100%",
    13795,"True","Unknown","True","False",
    13795,"True","False","False","Unknown"));
Assert(rgbs.Samples==1 && rgbs.BaseFrames==1 && rgbs.CurveFrames==1);
Assert(rgbs.V3.Status=="Live" && rgbs.LGC.Status=="Live" &&
       rgbs.LGD.Status=="Disabled");
var json=rgbs.ExportJson();
Assert(json.Contains(RgbTransportMonitor.Schema) &&
    json.Contains("RGBv3_CRC") && json.Contains("LGC_Cooldown"));
Assert(!json.Contains("LazyGForeverProbeDB"));
Assert(!json.Contains("characterName"));
Assert(json.Contains("LatestDecoded") &&
    json.Contains("CurvePlayerHealthBand") &&
    json.Contains("LgcGcd29515Active") &&
    json.Contains("80") && json.Contains("84") &&
    json.Contains("Unknown"));
rgbs.Accept(sample(s0.AddMilliseconds(500),44,10));
Assert(rgbs.V3.Status=="Live" && rgbs.LGC.Status=="Live");
rgbs.Accept(sample(s0.AddMilliseconds(1600),44,10));
Assert(rgbs.V3.Status=="Stale" && rgbs.LGC.Status=="Stale");
Assert(rgbs.V3.Frozen==1 && rgbs.LGC.Frozen==1);
rgbs.Accept(sample(s0.AddMilliseconds(1700),45,11));
Assert(rgbs.V3.Status=="Live" && rgbs.LGC.Status=="Live");
Assert(rgbs.V3.Recovered==1 && rgbs.LGC.Recovered==1);
rgbs.Accept(sample(s0.AddMilliseconds(1800),46,null));
Assert(rgbs.LGC.Status=="Missing" && rgbs.LGC.Reason=="StripNotFoundOrInvalid");
rgbs.Accept(sample(s0.AddMilliseconds(2000),47,12));
Assert(rgbs.LGC.Recovered==2);
rgbs.Accept(sample(s0.AddMilliseconds(2200),null,null,
    baseOk:false,foreground:false,curve:false));
Assert(rgbs.V3.Status=="Unavailable" &&
    rgbs.LGC.Status=="Unavailable" && rgbs.CaptureStatus=="Unavailable");
rgbs.Accept(sample(s0.AddMilliseconds(2400),48,13));
Assert(rgbs.V3.Recovered==2 && rgbs.LGC.Recovered==3);
Assert(rgbs.Summary().Contains("curve=OK"));
var cleanReport=rgbs.ExportJson();
Assert(cleanReport.Contains("MeanCaptureMilliseconds"));
Assert(cleanReport.Contains("BaseV2Frames"));
rgbs.Reset();
Assert(rgbs.Samples==0 && rgbs.LGC.Recovered==0);
Assert(rgbs.V3.Status=="NotObserved");
// No transport health report changes action gating:
Assert(ConditionEvaluator.GcdReady(attackBase)==Truth.Unknown);
Assert(XmlRotationDispatcher.Evaluate(parsed,attackBase,band04,now) is null);

Console.WriteLine("GameState, corpse safety, XML dispatch and preview regression: PASS");
void Assert(bool ok,[System.Runtime.CompilerServices.CallerLineNumber] int line=0)
{
    if(!ok)throw new Exception("GameState regression failed at line "+line);
}
