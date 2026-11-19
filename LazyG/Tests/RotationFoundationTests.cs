using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using LazyG.Desktop.Engine;
using LazyGPrototype;
static void Check(bool value,string message) {if(!value)throw new Exception("Foundation regression: "+message);}
// Structured XML -> Logitech HID -> WoW observational comparison log.
var execution=new RotationExecutionTrace(32);
execution.Start(DateTimeOffset.UtcNow,"forever/hunter/beast-mastery/PvE");
var execT=DateTimeOffset.UtcNow;
var recommendedId=execution.Recommend(execT,3044,"arcane-shot-priority");
Check(recommendedId>0,"XML recommendation is recorded independently");
var attemptId=execution.Attempt(execT.AddMilliseconds(50),3044,
    "arcane-shot-priority");
execution.DriverResult(execT.AddMilliseconds(90),3044,attemptId,true,
    "DeviceIoControl succeeded; result unknown");
execution.CastEvent(execT.AddMilliseconds(240),3044,true);
var compare=execution.ExportSummaryJson();
Check(compare.Contains("SAME_SPELL_EVENT_CAUSALITY_UNPROVEN") &&
    compare.Contains("arcane-shot-priority"),"matching LGE is not a cast causality claim");
execution.CastEvent(execT.AddMilliseconds(310),1130,true);
execution.Stop(execT.AddSeconds(1),"STOP");
Check(!execution.Recording && execution.ExportJsonl().Contains("SESSION_STOP"),
    "trace includes stop and can be exported");
var idleTrace=new RotationExecutionTrace();
idleTrace.Start(execT,"test");
idleTrace.Recommend(execT,3044,"test-rule");
Check(System.Text.Json.JsonDocument.Parse(idleTrace.ExportSummaryJson()).RootElement.GetProperty("hidAttempts").GetInt32()==0,
    "XML-only evaluation must not fabricate an input attempt");
idleTrace.Stop(execT.AddSeconds(1),"DONE");
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
// Synthetic fully observed family: the XML engine must see every rank's
// Learned status before choosing the highest verified usable concrete ID.
Dictionary<int,SpellState> KnownFamily(int baseId,int selectedRank)
{
    return HunterSpellFamilies.Ranks(baseId).ToDictionary(id=>id,id=>
        spell with {
            Learned=Observed<bool>.Known(id==selectedRank,now)
        });
}
Dictionary<int,SpellState> KnownHunter(params (int Base,int Rank)[] families)
{
    var all=new Dictionary<int,SpellState>();
    foreach(var (baseId,rank) in families)
        foreach(var (id,value) in KnownFamily(baseId,rank))
            all.Add(id,value);
    return all;
}
var state=empty with {
    Transport=Knowledge.Known,ClassId=Observed<int>.Known(3,now),
    SpecIndex=Observed<int>.Known(1,now),
    TargetExists=Observed<bool>.Known(true,now),TargetHostile=Observed<bool>.Known(true,now),
    TargetAlive=Observed<bool>.Known(true,now),GcdRemainingMilliseconds=Observed<int>.Known(0,now),
    PowerPercent=Observed<int>.Known(75,now),
    PowerBand=Observed<HealthBand>.Known(new HealthBand(75,79),now),
    Spells=KnownFamily(1130,1130)
};
var syntheticEval=RotationXmlV2.Evaluate(profile,state,null,now,"PvE");
Check(syntheticEval.Recommendation?.SpellId==1130,
    "simulation suggestion; "+syntheticEval.BlockReason+" "+
    string.Join(" | ",syntheticEval.Trace.Select(x=>x.Reason))+
    "; rank="+HunterSpellFamilies.Find(state,1130,now).Status+
    "; spellReady="+ConditionEvaluator.SpellReady(state,1130));
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
Check(ForeverHunterAbilityCatalog.All.Count>=35,
    "full Hunter reference catalog covers core BM, MM, SV and PvP families");
Check(ForeverHunterAbilityCatalog.Ranks(14323).Length==0,
    "catalog keyed by base ID only, prevents rank alias ambiguity");
Check(ForeverHunterAbilityCatalog.Find(19434)?.SharedCooldownGroup==
      ForeverHunterAbilityCatalog.Find(2643)?.SharedCooldownGroup,
    "Aimed and Multi share group in reference, not hardcoded cooldown time");
Check(ForeverHunterAbilityCatalog.Find(3044)?.SharedCooldownGroup==
      ForeverHunterAbilityCatalog.Find(1293241)?.SharedCooldownGroup,
    "Arcane and Summon Hawk shared group references");
Check(ForeverHunterAbilityCatalog.Find(1499)?.SharedCooldownGroup==
      ForeverHunterAbilityCatalog.Find(13795)?.SharedCooldownGroup,
    "traps reference one cooldown family");
Check(ForeverHunterAbilityCatalog.Ranks(1130)
    .SequenceEqual(HunterSpellFamilies.Ranks(1130)) &&
    ForeverHunterAbilityCatalog.Ranks(1978)
    .SequenceEqual(HunterSpellFamilies.Ranks(1978)) &&
    ForeverHunterAbilityCatalog.Ranks(3044)
    .SequenceEqual(HunterSpellFamilies.Ranks(3044)),
    "first four verified audit families remain consistent with full registry");
// User switches in a shared cooldown group must be exclusive across pages
// and cannot be persisted together, even through a corrupted JSON override.
Check(hunter.Settings["useArcaneShot"].ExclusiveGroup=="arcane" &&
    hunter.Settings["useSummonHawk"].ExclusiveGroup=="arcane" &&
    hunter.Settings["useAimedShot"].ExclusiveGroup=="shot" &&
    hunter.Settings["useMultiShot"].ExclusiveGroup=="shot" &&
    hunter.Settings["useImmolationTrap"].ExclusiveGroup=="trap" &&
    hunter.Settings["useExplosiveTrap"].ExclusiveGroup=="trap" &&
    hunter.Settings["useFreezingTrap"].ExclusiveGroup=="trap" &&
    hunter.Settings["useFrostTrap"].ExclusiveGroup=="trap",
    "all Hunter shared cooldown choices have XML groups");
var selectHawk=RotationSettingsExclusivity.Apply(hunter,
    new Dictionary<string,int>(),"useSummonHawk",1);
var hawkValues=RotationXmlV2.Resolve(hunter,selectHawk);
Check(hawkValues["useSummonHawk"]==1 && hawkValues["useArcaneShot"]==0,
    "Hawk switch automatically disables default Arcane Shot");
var selectArcane=RotationSettingsExclusivity.Apply(hunter,selectHawk,"useArcaneShot",1);
var arcaneValues=RotationXmlV2.Resolve(hunter,selectArcane);
Check(arcaneValues["useArcaneShot"]==1 && arcaneValues["useSummonHawk"]==0,
    "Arcane Shot switch automatically disables Hawk");
var selectMulti=RotationSettingsExclusivity.Apply(hunter,
    new Dictionary<string,int>(),"useMultiShot",1);
var selectAimed=RotationSettingsExclusivity.Apply(hunter,selectMulti,"useAimedShot",1);
Check(RotationXmlV2.Resolve(hunter,selectAimed)["useMultiShot"]==0 &&
    RotationXmlV2.Resolve(hunter,selectAimed)["useAimedShot"]==1,
    "Aimed and Multi are mutually exclusive");
var selectTrap=RotationSettingsExclusivity.Apply(hunter,
    new Dictionary<string,int>(),"useExplosiveTrap",1);
var switchTrap=RotationSettingsExclusivity.Apply(hunter,selectTrap,"useFreezingTrap",1);
Check(new[]{"useImmolationTrap","useExplosiveTrap","useFreezingTrap","useFrostTrap"}
    .Count(id=>RotationXmlV2.Resolve(hunter,switchTrap)[id]==1)==1 &&
    RotationXmlV2.Resolve(hunter,switchTrap)["useFreezingTrap"]==1,
    "changing traps turns off all other trap switches");
try {
    RotationXmlV2.Resolve(hunter,new Dictionary<string,int> {
        ["useSummonHawk"]=1, ["useArcaneShot"]=1
    });
    throw new Exception("Conflicting shared cooldown toggles accepted");
}
catch(FormatException) {}
Check(hunter.Settings["serpentManaMin"].Parent=="useSerpentSting" &&
    hunter.Settings["arcaneManaMin"].Parent=="useArcaneShot" &&
    hunter.Settings["useHuntersMark"].IconSpellId==1130,
    "WarMate-style nested sliders and spell icon metadata parsed");
// Synthetic compact v3 extension with two complete 2-rank families and
// one target debuff family. Bytes are independently asserted in Lua 5.1.
var compactManifest=new ProfileDataManifest("forever",3,1,"PvE",0xA1B2C3D4,
    new[]{new SpellFamilyRequirement(1130,new[]{1130,14323}),
          new SpellFamilyRequirement(3044,new[]{3044,14281})},
    new[]{new AuraFamilyRequirement("target",true,new[]{1130,14323})},
    new[]{"Identity","GcdActive","TargetEpoch"});
byte[] extension={
    0x4c,0x48,1,0xA1,0xB2,0xC3,0xD4,3,1,1,0,7,1,1,2,2,4,0,
    2,1,2,2,0x99,0x09
};
// A CRC-valid binding-only v3 frame does not contain GCD/ranks/auras.
var bindingOnly=new RgbV3Packet(new byte[(23+4+1)*3],0,1,0x4c47,0,4);
Check(HunterCompactProfileWire.Explain(bindingOnly,compactManifest,now)
    .StartsWith("BINDINGS_ONLY"),"v3 CRC with binding tail must not imply compact gameplay data");
Check(HunterCompactProfileWire.Explain(null,compactManifest,now)=="NO_V3_FRAME",
    "explicit diagnostic when compact frame absent");
Check(HunterCompactProfileWire.PayloadLength(compactManifest)==24 &&
    HunterCompactProfileWire.ExtensionCells(compactManifest)==8,
    "compact profile packs two spell families and target aura in 8 RGB cells");
byte[] BuildProfileFrame(byte[] body)
{
    int cells=23+HunterCompactProfileWire.ExtensionCells(compactManifest);
    var rgb=new byte[(cells+1)*3];
    byte[] markers={255,0,255,0,255,0,255,255,255,0,0,0};
    Array.Copy(markers,rgb,markers.Length);
    rgb[12]=1;rgb[13]=11;rgb[14]=4; // v3 direct8, current frame
    rgb[15]=0x4c;rgb[16]=0x47;rgb[17]=0x13; // Forever profile, Hunter BM
    Array.Copy(body,0,rgb,23*3,body.Length);
    ushort crc=RgbV3Codec.Crc16(rgb.AsSpan(12,cells*3-12));
    rgb[cells*3]=(byte)(crc>>8);rgb[cells*3+1]=(byte)crc;
    rgb[cells*3+2]=(byte)cells;
    return rgb;
}
Check(RgbV3Codec.TryDecode(BuildProfileFrame(extension),8,0x4c47,
    out var compactFrame,out var wireError),wireError);
Check(HunterCompactProfileWire.TryDecode(compactFrame,compactManifest,now,
    out var compact) && compact is not null,
    "v3 CRC plus full schema accepts compact Hunter states");
var compactBase=state with {Spells=new Dictionary<int,SpellState>(),
    Auras=new Dictionary<AuraKey,AuraState>()};
var mapped=HunterCompactProfileWire.ToGameState(compactBase,compact!);
Check(mapped.TargetEpoch.Is(x=>x==7)==Truth.True &&
    ConditionEvaluator.GcdReady(mapped)==Truth.True &&
    mapped.Spells[14323].Learned.Value==true &&
    mapped.Spells[1130].Learned.Value==false &&
    ConditionEvaluator.SpellReady(mapped,14323)==Truth.True &&
    mapped.Spells[14323].CooldownMs.Quality==Knowledge.Unknown &&
    ConditionEvaluator.SpellReady(mapped,14281)==Truth.False &&
    mapped.Auras[new AuraKey("target-epoch-7",14323,true)].Present.Value==true &&
    mapped.Auras[new AuraKey("target-epoch-7",1130,true)].Present.Value==false,
    "compact profile translates known booleans, learned ranks, epoch auras without synthetic CD ms");
Check(HunterCompactProfileWire.ToGameState(compactBase with {
    SpecIndex=Observed<int>.Known(2,now)},compact!).Spells.Count==0,
    "different spec cannot inherit Hunter profile observations");
var damagedCompact=(byte[])extension.Clone();
damagedCompact[3]^=1; // layout hash no longer matches, even with valid CRC
Check(RgbV3Codec.TryDecode(BuildProfileFrame(damagedCompact),8,0x4c47,
    out var wrongProfileFrame,out wireError) &&
    !HunterCompactProfileWire.TryDecode(wrongProfileFrame,compactManifest,now,out _),
    "full layout hash mismatch fails despite valid CRC");
var unknownEpoch=(byte[])extension.Clone();
unknownEpoch[10]=0;unknownEpoch[11]=0;unknownEpoch[12]=0;
Check(RgbV3Codec.TryDecode(BuildProfileFrame(unknownEpoch),8,0x4c47,
    out var noEpochFrame,out wireError) &&
    HunterCompactProfileWire.TryDecode(noEpochFrame,compactManifest,now,out var noEpoch) &&
    noEpoch!.Auras.Count==0,
    "unverified target epoch cannot claim absence or presence of target auras");
var secretRank=(byte[])extension.Clone();
secretRank[22]=0x9B; // first rank Protected, highest learned rank no longer provable
Check(RgbV3Codec.TryDecode(BuildProfileFrame(secretRank),8,0x4c47,
    out var secretFrame,out wireError) &&
    HunterCompactProfileWire.TryDecode(secretFrame,compactManifest,now,out var secret) &&
    ConditionEvaluator.SpellReady(
       HunterCompactProfileWire.ToGameState(compactBase,secret!),14323)==Truth.Unknown,
    "protected rank cannot authorize selected-rank readiness");
Check(ConditionEvaluator.SpellReady(mapped.Age(now.AddSeconds(2),
    TimeSpan.FromMilliseconds(900)),14323)==Truth.Unknown,
    "stale compact cooldown state does not authorize new casts");
var manifest=ProfileDataManifestBuilder.Build(hunter);
Check(manifest.LayoutHash==3034231383u &&
    manifest.SpellFamilies.Sum(x=>x.RankSpellIds.Count)==45 &&
    manifest.AuraFamilies.Sum(x=>x.RankSpellIds.Count)==13,
    "Lua BM manifest fingerprint matches embedded XML and reference rank families");
Check(manifest.Client=="forever" && manifest.ClassId==3 && manifest.SpecIndex==1 &&
    manifest.Mode=="PvE" && manifest.SpellFamilies.Count==11 &&
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
Check(hunter.Rules.Count==11 && hunter.Settings.Values
    .Where(x=>x.Type==RotationSettingType.Integer).All(x=>x.Step==5),
    "Hunter BM options plus 5-percent-only resource sliders");
Check(RotationProfileCatalog.Load("hunter","beast-mastery","PvP") is null,
    "Hunter PvP remains unavailable");
var hunterSpells=KnownHunter((1130,1130),(1978,1978),(3044,3044),(75,75));
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
// Universal command planning is explicitly disarmed until a verified SRC
// transport and a separately approved input driver exist.
// CRC v3 auto-bind extension: decode native HID, no user-entered mapping.
RgbV3Packet AutoFrame(byte generation,byte index,byte count,int id,
    byte modifier,byte usage,byte frame=1,int hunterCells=0)
{
    int extension=hunterCells+AutoBindingCodec.Cells;
    var rgb=new byte[(23+extension+1)*3];
    int offset=(23+hunterCells)*3;
    rgb[offset]=76;rgb[offset+1]=66;rgb[offset+2]=1;
    rgb[offset+3]=generation;rgb[offset+4]=index;rgb[offset+5]=count;
    rgb[offset+6]=(byte)(id>>16);rgb[offset+7]=(byte)(id>>8);
    rgb[offset+8]=(byte)id;rgb[offset+9]=modifier;rgb[offset+10]=usage;
    return new RgbV3Packet(rgb,0,frame,0x4c47,0,extension);
}
var autoRegistry=new AutoBindingRegistry();
Check(GHubKeys.TryParse("HID:3:4",out var autoMod,out var autoUsage) &&
    autoMod==3 && autoUsage==4,"auto key uses real HID Ctrl+Shift+A");
Check(!GHubKeys.TryParse("HID:16:4",out _,out _) &&
    !GHubKeys.TryParse("HID:1:0",out _,out _),"bad HID payload blocked");
var autoPacket=AutoFrame(1,1,2,3044,3,4);
Check(AutoBindingCodec.TryDecode(autoPacket,0,out var autoDecoded) &&
    autoDecoded?.SpellId==3044 && autoDecoded.Modifiers==3,
    "spell and modifier extracted from versioned RGB tail");
Check(autoRegistry.Accept(autoPacket,0,now) &&
    autoRegistry.Bindings(now)[3044]=="HID:3:4",
    "automatic binding is collected without manual file");
Check(autoRegistry.Accept(AutoFrame(1,2,2,75,0,58,2),0,
    now.AddMilliseconds(300)) &&
    autoRegistry.Bindings(now.AddMilliseconds(300)).Count==2,
    "multiple abilities accumulate through successive v3 frames");
Check(!autoRegistry.Accept(AutoFrame(1,2,2,75,0,58,2),0,
    now.AddMilliseconds(400)),"replayed frame ignored");
Check(autoRegistry.Accept(AutoFrame(2,1,1,75,2,58,3),0,
    now.AddMilliseconds(500)) &&
    !autoRegistry.Bindings(now.AddMilliseconds(500)).ContainsKey(3044) &&
    autoRegistry.Bindings(now.AddMilliseconds(500))[75]=="HID:2:58",
    "mapping generation replacement clears old spell binds");
Check(autoRegistry.Bindings(now.AddSeconds(47)).Count==0,
    "stale binding table cannot cause keypresses");
autoRegistry.Reset();
Check(autoRegistry.Accept(AutoFrame(1,1,1,3044,0,4,1,19),
    19,now),"Hunter compact and auto bindings coexist");
Check(!AutoBindingCodec.TryDecode(AutoFrame(1,1,1,3044,16,4),0,out _),
    "invalid modifier bits rejected");
Check(!AutoBindingCodec.TryDecode(AutoFrame(1,1,1,3044,0,0),0,out _),
    "missing HID code rejected");
autoRegistry.Reset();
Check(!autoRegistry.Accept(AutoFrame(0,1,1,3044,0,4),0,now) &&
    autoRegistry.Bindings(now).Count==0,"malformed RGB resets bindings");
// Legacy no-extension packets cannot be mistaken for trusted binding data.
Check(!autoRegistry.Accept(new RgbV3Packet(new byte[24*3],0,1,0x4c47,0,0),
    0,now) && autoRegistry.Bindings(now).Count==0,
    "old v3 remains valid but never authorizes key mapping");
var bindings=RotationKeyBindings.Parse("3044=F1\n75=F2");
Check(bindings[3044]=="F1" && RotationKeyBindings.Parse(
    RotationKeyBindings.Format(bindings)).Count==2,"binding roundtrip");
Check(GHubKeys.TryParse("CTRL+F2",out var hidMod,out var hidKey) && hidMod==1 && hidKey==59,
    "Logitech original HID modifier and F2");
Check(RotationKeyBindings.Parse("14283=CTRL+F2")[14283]=="CTRL+F2",
    "Logitech modifier bindings");
try { RotationKeyBindings.Parse("3044=F13"); throw new Exception("invalid key accepted"); }
catch(FormatException) {}
try { RotationKeyBindings.Parse("3044=F1\n3044=F2"); throw new Exception("duplicate accepted"); }
catch(FormatException) {}
var commandGate=new RotationCommandGate();
var chosen=new RotationRecommendation(RotationSourceId.Internal,3044,30,"arcane",now);
var verifiedSource=new RotationSourceSnapshot(RotationSourceId.Internal,
    RotationSourceHealth.Ready,1,1,now,null,"Ready");
Check(commandGate.TryPlan(chosen,verifiedSource,hunterState,now,false,true,
    bindings,out var disarmed) is null && disarmed=="DISARMED","no default execution");
Check(commandGate.TryPlan(chosen,verifiedSource,hunterState,now,true,false,
    bindings,out var unfocused) is null && unfocused=="WOW NOT FOREGROUND","focus gate");
Check(commandGate.TryPlan(chosen,verifiedSource with {Confirmed=null},hunterState,
    now,true,true,bindings,out var unconfirmed) is null &&
    unconfirmed=="UNVERIFIED SOURCE","source transport must be confirmed");
Check(commandGate.TryPlan(chosen,verifiedSource,hunterState,now,true,true,
    bindings,out var planned)?.Key=="F1" && planned=="AUTHORIZED FOR LOGITECH DRIVER",
    "common command is only planned on fully verified evidence");
Check(commandGate.TryPlan(chosen,verifiedSource,hunterState,now.AddMilliseconds(300),
    true,true,bindings,out var repeated) is null &&
    repeated=="FRAME ALREADY HANDLED","same frame cannot replay");
Check(commandGate.TryPlan(chosen with {At=now.AddMilliseconds(500)},
    verifiedSource with {ReceivedAt=now.AddMilliseconds(500)},
    hunterState with {CapturedAt=now.AddMilliseconds(500)},now.AddMilliseconds(500),
    true,true,bindings,out _)?.Key=="F1","fresh frame may create next plan");
commandGate.Reset();
Check(commandGate.TryPlan(chosen,verifiedSource,GameState.Empty(now),now,true,true,
    bindings,out var stale) is null && stale=="STALE GAMESTATE",
    "unknown game state cannot authorize command");
// Start/Stop arms ONLY a fresh XML recommendation preview; it does not send
// keys and never replays the last spell when RGB becomes unknown or stale.
var previewSession=new RotationPreviewSession();
Check(!previewSession.Running && previewSession.Current is null,
    "preview starts stopped with no cached recommendation");
try {
    previewSession.Start(paladin,new Dictionary<string,int>());
    throw new Exception("wrong class preview was accepted");
} catch(InvalidOperationException) {}
previewSession.Start(hunter,new Dictionary<string,int>());
Check(previewSession.Running && previewSession.Current is null,
    "start arms read-only evaluation without a previous suggestion");
Check(previewSession.Update(hunterState,now)?.SpellId==3044,
    "preview uses XML recommendation on a confirmed fresh state");
Check(previewSession.Update(GameState.Empty(now),now) is null &&
    previewSession.Current is null,
    "loss of RGB immediately clears old suggested spell");
Check(previewSession.Update(hunterState,now)?.SpellId==3044,
    "new known sample can restore a recommendation");
Check(previewSession.Update(hunterState,now.AddSeconds(2)) is null &&
    previewSession.Current is null,
    "stale frame never replays the last suggestion");
previewSession.Stop();
Check(!previewSession.Running &&
    previewSession.Update(hunterState,now) is null &&
    previewSession.Current is null,
    "Stop clears all suggestions, even when a valid frame arrives");
try {
    previewSession.Start(hunter,new Dictionary<string,int> {
        ["useArcaneShot"]=1,["useSummonHawk"]=1
    });
    throw new Exception("conflicting profile settings started");
} catch(FormatException) {}
Check(!previewSession.Running,"invalid settings cannot arm preview");
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
var higherRankHunter=hunterState with {
    Spells=KnownHunter((1130,14323),(1978,13551),(3044,14283),(75,75))
};
Check(RotationXmlV2.Evaluate(hunter,higherRankHunter,null,now,"PvE")
    .Recommendation?.SpellId==14283,
    "Hunter Arcane rule recommends confirmed rank 14283 instead of base 3044");
Check(RotationXmlV2.Evaluate(hunter,higherRankHunter with {
    Auras=absentMarkRanks
},null,now,"PvE").Recommendation?.SpellId==14323,
    "Hunter Mark rule chooses confirmed rank 14323 if debuff fully absent");
var partialFamily=KnownHunter((1130,14323),(1978,13551),(3044,14283),(75,75));
partialFamily.Remove(14287);
Check(RotationXmlV2.Evaluate(hunter,higherRankHunter with {
    Spells=partialFamily
},null,now,"PvE").Recommendation?.SpellId==75,
    "missing possible higher Arcane rank blocks Arcane rather than guessing");
partialFamily[14287]=partialFamily[14286] with {
    Learned=Observed<bool>.Missing(Knowledge.Protected)
};
Check(RotationXmlV2.Evaluate(hunter,higherRankHunter with {
    Spells=partialFamily
},null,now,"PvE").Recommendation?.SpellId==75,
    "protected rank blocks Arcane while allowing independently verified Auto Shot");
var rankWithoutUsable=KnownHunter((1130,14323),(1978,13551),(3044,14283),(75,75));
rankWithoutUsable[14283]=rankWithoutUsable[14283] with {
    Usable=Observed<bool>.Missing(Knowledge.Protected)
};
Check(RotationXmlV2.Evaluate(hunter,higherRankHunter with {
    Spells=rankWithoutUsable
},null,now,"PvE").Recommendation?.SpellId==75,
    "unavailable readiness of highest rank cannot fall back to lower ranks");
Check(RotationXmlV2.Evaluate(hunter,higherRankHunter,null,
    now.AddSeconds(2),"PvE").Recommendation is null,
    "stale verified rank cannot generate a new recommendation");
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
var partialHunterState=hunterState with {
    Spells=new Dictionary<int,SpellState>{{1130,spell},{1978,spell},
        {3044,spell},{75,spell}}
};
var hunterRankUnknown=HunterSpellFamilies.Find(partialHunterState,1130,now);
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
Check(beforeAudit.Conditions.Any(x=>x.Contains("Rank 1130=VerifiedLearnedRank")),
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
var missingBefore=HunterAuditReadiness.Missing(partialHunterState,now);
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
