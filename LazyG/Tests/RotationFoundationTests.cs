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
    Spells=new Dictionary<int,SpellState>{{1130,spell}}
};
Check(RotationXmlV2.Evaluate(profile,state,null,now,"PvE").Recommendation?.SpellId==1130,"simulation suggestion");
Check(RotationXmlV2.Evaluate(profile,state,new Dictionary<string,int>{{"powerThreshold",80}},now,"PvE").Recommendation is null,"slider changes rule");
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
Console.WriteLine("Rotation foundation v2 offline regression: PASS");
