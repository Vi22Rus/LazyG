using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using LazyG.Desktop.Engine;
static void Check(bool value,string message) {if(!value)throw new Exception("Foundation regression: "+message);}
var now=DateTimeOffset.UtcNow;
string xml=File.ReadAllText(Path.Combine("LazyG","Rotations","Forever","Examples","synthetic-v2.xml"));
var profile=RotationXmlV2.Parse(xml);
Check(profile.ClassId==3 && profile.Settings.Count==2,"profile metadata");
Check(RotationXmlV2.Resolve(profile,new Dictionary<string,int>{{"powerThreshold",80}})["powerThreshold"]==80,"override");
void Reject(string broken)
{
    try {RotationXmlV2.Parse(broken);throw new Exception("Invalid XML was accepted");}
    catch(FormatException) {}
}
Reject(xml.Replace("version=\"2\"","version=\"1\""));
Reject(xml.Replace("powerThreshold\"/>","missing\"/>"));
Reject(xml.Replace("min=\"0\" max=\"100\" step=\"5\"","min=\"0\" max=\"100\" step=\"6\""));
Reject(xml.Replace("<Rules>","<!DOCTYPE unsafe [<!ENTITY xxe SYSTEM \"file:///etc/passwd\">]><Rules>"));
Reject(xml.Replace("classId=\"3\"","classId=\"13\"").Replace("mode=\"PvE\"","mode=\"NotAMode\""));
try {RotationXmlV2.Resolve(profile,new Dictionary<string,int>{{"powerThreshold",83}});throw new Exception("bad override accepted");}
catch(FormatException) {}
var empty=GameState.Empty(now);
Check(RotationXmlV2.Evaluate(profile,empty,null,now,"PvE").Recommendation is null,"unknown identity never suggests");
var spell=new SpellState(Observed<bool>.Known(true,now),Observed<bool>.Known(true,now),
    Observed<bool>.Missing(),Observed<int>.Known(0,now),Observed<int>.Missing());
var state=empty with {
    Transport=Knowledge.Known,ClassId=Observed<int>.Known(3,now),
    SpecIndex=Observed<int>.Known(1,now),
    TargetExists=Observed<bool>.Known(true,now),TargetHostile=Observed<bool>.Known(true,now),
    TargetAlive=Observed<bool>.Known(true,now),GcdRemainingMilliseconds=Observed<int>.Known(0,now),
    PowerPercent=Observed<int>.Known(75,now),
    PowerBand=Observed<HealthBand>.Known(new HealthBand(75,79),now),
    Spells=new Dictionary<int,SpellState>{{1130,spell}}
};
Check(RotationXmlV2.Evaluate(profile,state,null,now,"PvE").Recommendation?.SpellId==1130,"simulation suggestion");
Check(RotationXmlV2.Evaluate(profile,state,new Dictionary<string,int>{{"powerThreshold",80}},now,"PvE").Recommendation is null,"slider changes rule");
Check(RotationXmlV2.Evaluate(profile,state,new Dictionary<string,int>{{"powerThreshold",80}},now,"PvE").Trace[0].Reason.Contains("powerThreshold=80"),"trace reports effective slider value");
Check(RotationXmlV2.Evaluate(profile,state,new Dictionary<string,int>{{"useExample",0}},now,"PvE").Recommendation is null,"toggle changes rule");
Check(RotationXmlV2.Evaluate(profile,state,null,now,"PvP").Recommendation is null,"mode isolation");
Check(RotationXmlV2.Evaluate(profile,state with { TargetAlive=Observed<bool>.Missing() },null,now,"PvE").Recommendation is null,"unknown life blocks");
Check(RotationXmlV2.Evaluate(profile,state,null,now.AddSeconds(2),"PvE").Recommendation is null,"stale snapshot");
Check(RotationXmlV2.Evaluate(profile,state with { GcdRemainingMilliseconds=Observed<int>.Missing() },null,now,"PvE").Recommendation is null,"unknown GCD");
var sources=new RotationSourceManager();
Check(!sources.CanUseInternal(now),"not connected cannot fallback");
Check(sources.Accept(RotationSourceId.Internal,true,true,1,1,null,now),"internal confirmation");
Check(sources.CanUseInternal(now),"confirmed internal");
Check(sources.Accept(RotationSourceId.Hekili,true,true,2,1,1130,now.AddMilliseconds(5)),"external confirmed");
Check(!sources.CanUseInternal(now),"external disables internal");
Check(sources.ExternalRecommendation(now.AddMilliseconds(5))?.SpellId==1130,"external suggestion");
Check(!sources.Accept(RotationSourceId.Hekili,true,true,2,1,1130,now.AddMilliseconds(6)),"duplicate rejected");
Check(sources.ExternalRecommendation(now.AddMilliseconds(6)) is null,"duplicate clears recommendation");
Check(!sources.Accept(RotationSourceId.Hekili,true,true,2,1,1130,now.AddMilliseconds(6)),"duplicate after disconnect still rejected");
Check(sources.Accept(RotationSourceId.JustAC,true,true,3,1,null,now.AddMilliseconds(7)),"no-recommendation status accepted");
Check(sources.ExternalRecommendation(now.AddMilliseconds(7)) is null,"no old recommendation");
Check(sources.Snapshot(now.AddSeconds(2)).Health==RotationSourceHealth.Stale,"freshness");
sources.Disconnect("RGB unavailable");
Check(!sources.CanUseInternal(now) && sources.ExternalRecommendation(now) is null,"fail closed");
var folder=Path.Combine(Path.GetTempPath(),"LazyG-rotation-test-"+Guid.NewGuid().ToString("N"));
try {
    var file=Path.Combine(folder,"forever-hunter-pve.json");
    RotationSettingsStore.Save(file,profile,new Dictionary<string,int>{{"powerThreshold",80}});
    Check(RotationSettingsStore.Load(file,profile)["powerThreshold"]==80,"persist override");
    RotationSettingsStore.Save(file,profile,new Dictionary<string,int>{{"powerThreshold",85}});
    Check(File.Exists(file+".bak"),"backup exists");
    Check(RotationSettingsStore.Load(file,profile)["powerThreshold"]==85,"updated override");
    RotationSettingsStore.Reset(file,profile);
    Check(RotationSettingsStore.Load(file,profile).Count==0,"reset removes override");
    try {
        RotationSettingsStore.Load(file,profile with {SpecIndex=2});
        throw new Exception("Wrong spec was accepted");
    } catch(InvalidDataException) {}
    File.WriteAllText(file,"{broken json");
    try {RotationSettingsStore.Load(file,profile);throw new Exception("Bad JSON accepted");}
    catch(InvalidDataException) {}
} finally {if(Directory.Exists(folder))Directory.Delete(folder,true);}
var supportDir=Path.Combine(Path.GetTempPath(),"LazyG-support-test-"+Guid.NewGuid().ToString("N"));
try {
    var archive=LazyG.Desktop.Diagnostics.RotationSupportArchive.Create(supportDir,
        new("0.4.0-dev","Internal","Ready","C:\\Users\\Secret\\token","forever",
            "SecretCharacter",12,2,3,4),"SecretPassword=123",false,now);
    using var zip=System.IO.Compression.ZipFile.OpenRead(archive);
    Check(zip.Entries.Count>=7,"support ZIP contents");
    var names=string.Join(",",zip.Entries.Select(x=>x.FullName));
    Check(names.Contains("rotation-state.json") && names.Contains("rgb-health.json"),"support sections");
    foreach(var entry in zip.Entries) {
        using var reader=new StreamReader(entry.Open());
        var data=reader.ReadToEnd();
        Check(!data.Contains("Secret") && !data.Contains("Password") && !data.Contains("token"),"redaction");
    }
} finally {if(Directory.Exists(supportDir))Directory.Delete(supportDir,true);}

var paladin=RotationProfileCatalog.Load("paladin","retribution","PvP")!;
Check(paladin.Client=="forever" && paladin.ClassId==2 && paladin.SpecIndex==3,"paladin profile isolation");
Check(RotationProfileCatalog.Load("paladin","retribution","PvE") is null &&
    RotationProfileCatalog.Status("mage","fire","PvP")=="Unavailable","no forged other specs");
Check(RotationProfileCatalog.Load("warrior","arms","PvE")!.Rules[0].SpellId==12294,"Arms fixture");
var paladinState=state with {ClassId=Observed<int>.Known(2,now),
    SpecIndex=Observed<int>.Known(3,now),
    Spells=new Dictionary<int,SpellState>{{853,spell}},
    TargetHealthPercent=Observed<int>.Missing()};
Check(RotationXmlV2.Evaluate(paladin,paladinState,null,now,"PvP").Recommendation?.SpellId==853,
    "Hammer control not intrinsically limited by 20 percent");
Check(RotationXmlV2.Evaluate(paladin,paladinState,
    new Dictionary<string,int>{{"onlyLowHpHammer",1}},now,"PvP").Recommendation is null,
    "opt-in low HP requires known signal");
Check(RotationXmlV2.Evaluate(paladin,paladinState with {
    TargetHealthPercent=Observed<int>.Known(18,now)},
    new Dictionary<string,int>{{"onlyLowHpHammer",1}},now,"PvP").Recommendation?.SpellId==853,
    "HP threshold 20 permits known 18");
Check(RotationXmlV2.Evaluate(paladin,paladinState with {
    TargetHealthPercent=Observed<int>.Known(40,now)},
    new Dictionary<string,int>{{"onlyLowHpHammer",1}},now,"PvP").Recommendation is null,
    "HP threshold prevents known 40");
Check(RotationXmlV2.Evaluate(paladin,paladinState,new Dictionary<string,int>{{"onlyLowHpHammer",1}},now,"PvP").Trace[0].Reason.Contains("TargetHealthPercent Below hammerHpThreshold=20"),"PvP trace includes conditional threshold");
Check(RotationXmlV2.Evaluate(paladin,paladinState,
    new Dictionary<string,int>{{"useHammerOfJustice",0}},now,"PvP").Recommendation is null,
    "user can disable control");

// Hunter BM at level 30: RGB Curve 5%-range threshold tests, never raw exact power.
var hunter=RotationProfileCatalog.Load("hunter","beast-mastery","PvE")!;
var manifest=ProfileDataManifestBuilder.Build(hunter);
Check(manifest.Client=="forever" && manifest.ClassId==3 && manifest.SpecIndex==1 &&
    manifest.Mode=="PvE" && manifest.SpellFamilies.Count==4 &&
    manifest.AuraFamilies.Count==2 &&
    manifest.Signals.Contains("GcdActive") &&
    manifest.Signals.Contains("TargetEpoch") &&
    manifest.Signals.Contains("PowerBand5"),
    "Hunter BM profile manifest extracts spell ranks, aura families, GCD and Curve requirements");
Check(manifest.SpellFamilies.Single(x=>x.BaseSpellId==3044)
    .RankSpellIds.SequenceEqual(HunterSpellFamilies.Ranks(3044)),
    "manifest contains all Arcane Shot ranks, never only base SpellID");
Check(manifest.AuraFamilies.Single(x=>x.RankSpellIds.Contains(1130))
    .RankSpellIds.SequenceEqual(HunterSpellFamilies.Ranks(1130)),
    "manifest preserves every Hunter Mark debuff rank");
Check(manifest.CompatibleWith("forever",3,1,"PvE",manifest.LayoutHash) &&
    !manifest.CompatibleWith("forever",3,2,"PvE",manifest.LayoutHash) &&
    !manifest.CompatibleWith("335",3,1,"PvE",manifest.LayoutHash) &&
    !manifest.CompatibleWith("forever",3,1,"PvE",manifest.LayoutHash^1),
    "schema hash and client/spec mismatch rejected");
Check(ProfileDataManifestBuilder.Build(hunter).LayoutHash==manifest.LayoutHash,
    "profile schema hash deterministic");
Check(ProfileDataManifestBuilder.Build(hunter with {
    Rules=hunter.Rules.Reverse().ToArray()
}).LayoutHash==manifest.LayoutHash,
    "schema hash independent of XML priority order");
Check(ProfileDataManifestBuilder.Build(hunter with {
    Rules=hunter.Rules.Take(3).ToArray()
}).LayoutHash!=manifest.LayoutHash,
    "profile schema hash changes when ability set changes");
Check(hunter.Rules.Count==4 && hunter.Settings.Values
    .Where(x=>x.Type==RotationSettingType.Integer).All(x=>x.Step==5),
    "Hunter BM four rules and 5-percent-only resource sliders");
Check(RotationProfileCatalog.Load("hunter","beast-mastery","PvP") is null,
    "Hunter PvP remains unavailable");
var hunterSpells=new Dictionary<int,SpellState> {
    [1130]=spell,[1978]=spell,[3044]=spell,[75]=spell
};
var hunterState=state with {
    Spells=hunterSpells,
    TargetEpoch=Observed<int>.Known(7,now),
    PowerBand=Observed<HealthBand>.Known(new HealthBand(25,29),now),
    Auras=new Dictionary<AuraKey,AuraState> {
        [new AuraKey("target-epoch-7",1130,true)]=new(
            Observed<bool>.Known(true,now),Observed<int>.Missing(),Observed<int>.Missing()),
        [new AuraKey("target-epoch-7",1978,true)]=new(
            Observed<bool>.Known(true,now),Observed<int>.Missing(),Observed<int>.Missing())
    }
};
var hunterEval=RotationXmlV2.Evaluate(hunter,hunterState,null,now,"PvE");
Check(hunterEval.Recommendation?.SpellId==3044,"Hunter Arcane Shot selected from 25-29 band");
Check(hunterEval.Trace.Any(t=>t.Reason.Contains("CurveBand")),
    "Hunter trace contains resource interval");
Check(RotationXmlV2.Evaluate(hunter,
    hunterState with {PowerBand=Observed<HealthBand>.Known(new HealthBand(20,24),now)},
    null,now,"PvE").Recommendation?.SpellId==75,
    "below 25% band only Auto Shot meets configured priority");
Check(RotationXmlV2.Evaluate(hunter,
    hunterState with {PowerBand=Observed<HealthBand>.Missing()},
    null,now,"PvE").Recommendation?.SpellId==75,
    "missing Curve does not authorize resource-dependent spells");
Check(RotationXmlV2.Evaluate(hunter,
    hunterState with {PowerBand=Observed<HealthBand>.Known(new HealthBand(25,29),now)},
    new Dictionary<string,int>{{"arcaneManaMin",30}},now,"PvE").Recommendation?.SpellId==75,
    "5% slider change immediately changes selected ability");
Check(RotationXmlV2.Evaluate(hunter,
    hunterState with {PowerBand=Observed<HealthBand>.Known(new HealthBand(30,34),now)},
    new Dictionary<string,int>{{"arcaneManaMin",30}},now,"PvE").Recommendation?.SpellId==3044,
    "30-34 interval satisfies 30% lower bound");
var absentMarkRanks=HunterSpellFamilies.Ranks(1130).ToDictionary(
    id=>new AuraKey("target-epoch-7",id,true),
    id=>new AuraState(Observed<bool>.Known(false,now),
        Observed<int>.Missing(),Observed<int>.Missing()));
Check(RotationXmlV2.Evaluate(hunter,
    hunterState with {Auras=absentMarkRanks},
    null,now,"PvE").Recommendation?.SpellId==1130,
    "all known absent mark ranks on current target allow refresh");
var partialMark=new Dictionary<AuraKey,AuraState> {
    [new AuraKey("target-epoch-7",1130,true)]=new(
        Observed<bool>.Known(false,now),Observed<int>.Missing(),Observed<int>.Missing())
};
Check(RotationXmlV2.Evaluate(hunter,
    hunterState with {Auras=partialMark},null,now,"PvE").Trace[0].Outcome==Truth.Unknown,
    "one absent base rank cannot prove entire Mark family is absent");
var rankMarkPresent=new Dictionary<AuraKey,AuraState>(absentMarkRanks) {
    [new AuraKey("target-epoch-7",14323,true)]=new(
        Observed<bool>.Known(true,now),Observed<int>.Missing(),Observed<int>.Missing())
};
Check(RotationXmlV2.Evaluate(hunter,
    hunterState with {Auras=rankMarkPresent},null,now,"PvE").Trace[0].Outcome==Truth.False,
    "higher-rank Mark on target must not trigger base-rank refresh");
Check(RotationXmlV2.Evaluate(hunter,
    hunterState with {TargetEpoch=Observed<int>.Missing()},
    null,now,"PvE").Trace[0].Outcome==Truth.Unknown,
    "missing target epoch never establishes absent mark");
Check(RotationXmlV2.Evaluate(hunter,
    hunterState with {TargetEpoch=Observed<int>.Known(8,now)},
    null,now,"PvE").Trace[0].Outcome==Truth.Unknown,
    "old target epoch aura must not carry to new target");
Check(RotationXmlV2.Evaluate(hunter,
    hunterState with {PowerBand=Observed<HealthBand>.Known(new HealthBand(25,29),now)},
    null,now.AddSeconds(2),"PvE").Recommendation is null,"Hunter stale state blocks");
Reject(File.ReadAllText(Path.Combine("LazyG","Rotations","Forever","Experimental",
    "hunter-beast-mastery-pve.xml")).Replace("step=" + (char)34 + "5" + (char)34, "step=" + (char)34 + "3" + (char)34));

// Hunter rank audit: never infer a learned rank from character level or base SpellID.
var hunterRankUnknown=HunterSpellFamilies.Find(hunterState,1130,now);
Check(hunterRankUnknown.SelectedRank is null &&
    hunterRankUnknown.Status=="RankSetUnverified","partial rank evidence cannot assert max rank");
int[] markRanks=HunterSpellFamilies.Ranks(1130);
var rankState=hunterState with {
    Spells=markRanks.ToDictionary(x=>x,x=>spell with {
        Learned=Observed<bool>.Known(x==14323,now)
    })
};
var foundRank=HunterSpellFamilies.Find(rankState,1130,now);
Check(foundRank.SelectedRank==14323,"verified learned Hunter mark rank chosen from full family");
Check(HunterSpellFamilies.BaseId(14323)==1130 &&
    HunterSpellFamilies.BaseId(13549)==1978,"rank family lookup");
Check(HunterSpellFamilies.Find(rankState,1130,now.AddSeconds(2)).SelectedRank is null,
    "stale rank observation blocked");
var audit=new HunterRotationAudit(3);
var beforeAudit=audit.Capture(hunter,hunterState,null,now);
Check(beforeAudit.ExpectedSpellId==3044 &&
    beforeAudit.Verdict==RotationAuditVerdict.Unobservable,"XML expectation is not cast evidence");
Check(beforeAudit.Conditions.Any(x=>x.Contains("Rank 1130=RankSetUnverified")),
    "audit identifies unverified Hunter learned rank");
Check(audit.Observe(new(3044,now.AddMilliseconds(100),
    RotationCastEvidence.None,7,true)) is null,"unverified cast attempt ignored");
Check(audit.Observe(new(3044,now.AddMilliseconds(100),
    RotationCastEvidence.CombatLogSuccess,7,false)) is null,
    "cast from unverified player cannot be matched");
Check(audit.Observe(new(14281,now.AddMilliseconds(200),
    RotationCastEvidence.CombatLogSuccess,8,true)) is null,
    "target-epoch mismatch cannot establish execution");
var verified=audit.Observe(new(14281,now.AddMilliseconds(200),
    RotationCastEvidence.CombatLogSuccess,7,true));
Check(verified?.Verdict==RotationAuditVerdict.Match &&
    verified.ObservedSpellId==14281,"trusted same-family cast observation matches");
var mismatchAudit=new HunterRotationAudit();
mismatchAudit.Capture(hunter,hunterState,null,now);
var mismatch=mismatchAudit.Observe(new(75,now.AddMilliseconds(300),
    RotationCastEvidence.CombatLogSuccess,7,true));
Check(mismatch?.Verdict==RotationAuditVerdict.Mismatch &&
    mismatch.Reason.Contains("AttributionUnproven"),"different observed cast is correlation, not LazyG fault");
var noProofAudit=new HunterRotationAudit(2);
noProofAudit.Capture(hunter,hunterState,null,now);
Check(noProofAudit.Observe(new(3044,now.AddSeconds(3),
    RotationCastEvidence.CombatLogSuccess,7,true)) is null,
    "old expected frame cannot be matched to future cast");
noProofAudit.Capture(hunter,hunterState,null,now.AddMilliseconds(400));
noProofAudit.Capture(hunter,hunterState,null,now.AddMilliseconds(800));
Check(noProofAudit.Rows.Count==2,"audit log bounded");
Check(noProofAudit.ExportJson().Contains("NoVerifiedCastEvent") &&
    !noProofAudit.ExportJson().Contains("target-epoch-7"),"export is safe, no identity keys");
Console.WriteLine("Hunter rank and rotation audit regression: PASS");


// LGE optional cast-event transport: strict schema, checksum and event-only verdict.
byte[] lge={0x4c,0x47,0x45,1,5,0,0x0b,0xe4,0,7,1,0,0,0,0,0xa5,0,0};
int lgeSum=0;
for(int n=0;n<16;n++)lgeSum=(lgeSum+lge[n])&255;
lge[16]=(byte)lgeSum;lge[17]=(byte)(255-lgeSum);
Check(LazyG.Desktop.Diagnostics.ForeverCastEventCodec.TryDecode(lge,out var castEvent) &&
    castEvent?.SpellId==3044 && castEvent.TargetEpoch==7,
    "LGE valid player-cast event");
var idle=(byte[])lge.Clone();
idle[4]=0;idle[5]=0;idle[6]=0;idle[7]=0;idle[10]=0;
int idleSum=0;for(int n=0;n<16;n++)idleSum=(idleSum+idle[n])&255;
idle[16]=(byte)idleSum;idle[17]=(byte)(255-idleSum);
Check(LazyG.Desktop.Diagnostics.ForeverCastEventCodec.TryDecode(idle,out var idlePacket) &&
    idlePacket is {PlayerEvent:false,SpellId:0,Sequence:0},
    "LGE heartbeat establishes baseline before first cast");
var corrupted=(byte[])lge.Clone();corrupted[7]^=1;
Check(!LazyG.Desktop.Diagnostics.ForeverCastEventCodec.TryDecode(corrupted,out _),
    "LGE CRC rejects corrupted bytes");
var spoof=(byte[])lge.Clone();spoof[10]=0;
Check(!LazyG.Desktop.Diagnostics.ForeverCastEventCodec.TryDecode(spoof,out _),
    "LGE non-player event blocked");
var auditEvent=new HunterRotationAudit();
auditEvent.Capture(hunter,hunterState,null,now);
var eventOnly=auditEvent.Observe(new(3044,now.AddMilliseconds(150),
    RotationCastEvidence.UnitSpellcastSucceeded,7,true));
Check(eventOnly?.Verdict==RotationAuditVerdict.EventOnly &&
    eventOnly.Reason.Contains("EffectUnverified"),
    "UNIT_SPELLCAST_SUCCEEDED must never prove hit or effect");

// Readiness audit never invents aura/rank/target/GCD from Curve or event hints.
var missingBefore=HunterAuditReadiness.Missing(hunterState,now);
Check(missingBefore.Contains("VerifiedRank:1130") &&
      missingBefore.Contains("GcdReady")==false &&
      missingBefore.Contains("TargetDebuffRanks:1130"),
      "readiness distinguishes verified synthetic global gate from missing rank evidence");
Check(HunterAuditReadiness.Missing(GameState.Empty(now),now).Contains("CurveManaBand"),
    "unknown Curve explicitly reported");
Check(HunterAuditReadiness.Missing(hunterState,now.AddSeconds(2)).Contains("GcdReady"),
    "stale GCD explicitly reported");
var eventCategories=new HunterRotationAudit();
eventCategories.Capture(hunter,hunterState,null,now);
var aligned=eventCategories.Observe(new(14281,now.AddMilliseconds(100),
    RotationCastEvidence.UnitSpellcastSucceeded,7,true));
Check(aligned?.Verdict==RotationAuditVerdict.EventOnly &&
      aligned.Reason.Contains("SameFamily"),"same-family event is still effect unverified");
eventCategories.RecordUncorrelatedEvent();
eventCategories.RecordDuplicateEvent();
Check(eventCategories.ExportJson().Contains("SameRuleFamily") &&
      eventCategories.ExportJson().Contains("missingCapabilities") &&
      eventCategories.Summary().Contains("unmatched=1"),
      "audit distinguishes aligned player event, gaps and unmatched traffic");

Console.WriteLine("Rotation foundation v2 offline regression: PASS");
