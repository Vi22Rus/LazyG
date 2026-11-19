using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;

namespace LazyG.Desktop.Engine;

// One vendor-neutral command contract. G HUB users may assign their hardware
// macro/profile keys to the same F-keys; this is not a G HUB SDK connection.
internal sealed record RotationKeyCommand(int SpellId, string Key, RotationSourceId Source,
    long SourceEpoch, DateTimeOffset SnapshotAt);

internal static class RotationKeyBindings
{
    public static IReadOnlyDictionary<int,string> Parse(string text)
    {
        if(text.Length>4096)throw new FormatException("Binding text too long");
        var result=new Dictionary<int,string>();
        foreach(var line in text.Replace("\r","").Split('\n'))
        {
            var clean=line.Trim();
            if(clean.Length==0 || clean.StartsWith('#'))continue;
            var split=clean.Split('=',2);
            if(split.Length!=2 || !int.TryParse(split[0].Trim(),out int id) ||
               id<=0 || id>16777215)throw new FormatException("Expected SpellID=F1..F12");
            var key=split[1].Trim().ToUpperInvariant();
            if(!int.TryParse(key.StartsWith("F",StringComparison.Ordinal)?key[1..]:"",out int f) ||
                f<1 || f>12)throw new FormatException("Only F1..F12 are supported");
            if(!result.TryAdd(id,key))throw new FormatException("Duplicate SpellID");
        }
        if(result.Count>128)throw new FormatException("Too many bindings");
        return result;
    }
    public static string Format(IReadOnlyDictionary<int,string> values) =>
        string.Join("\n",values.OrderBy(x=>x.Key).Select(x=>x.Key+"="+x.Value));
    public static void Save(string path,IReadOnlyDictionary<int,string> values)
    {
        Parse(Format(values));
        var directory=Path.GetDirectoryName(path);
        if(string.IsNullOrWhiteSpace(directory))throw new ArgumentException("No directory",nameof(path));
        Directory.CreateDirectory(directory);
        var temp=path+".tmp";
        File.WriteAllText(temp,JsonSerializer.Serialize(values));
        File.Move(temp,path,true);
    }
    public static IReadOnlyDictionary<int,string> Load(string path)
    {
        if(!File.Exists(path))return new Dictionary<int,string>();
        var data=JsonSerializer.Deserialize<Dictionary<int,string>>(File.ReadAllText(path)) ??
            throw new FormatException("Empty bindings");
        return Parse(Format(data));
    }
}

// This is an authorization PLANNER, not an input driver. A positive decision
// never proves that a key was sent or a spell was cast. No caller in the current
// 0.4.0-dev build sends keys. The separate verified source transport is a gate.
internal sealed class RotationCommandGate
{
    private DateTimeOffset lastIssuedAt;
    private DateTimeOffset lastSnapshotAt;
    private long lastEpoch=-1;
    private RotationSourceId? lastSource;
    public void Reset()
    {
        lastIssuedAt=default;lastSnapshotAt=default;lastEpoch=-1;lastSource=null;
    }
    public RotationKeyCommand? TryPlan(RotationRecommendation? recommendation,
        RotationSourceSnapshot source, GameState state, DateTimeOffset now,
        bool explicitlyArmed, bool gameForeground, IReadOnlyDictionary<int,string> bindings,
        out string reason)
    {
        reason="BLOCKED";
        if(!explicitlyArmed){reason="DISARMED";return null;}
        if(!gameForeground){reason="WOW NOT FOREGROUND";return null;}
        if(recommendation is null){reason="NO RECOMMENDATION";return null;}
        if(source.Confirmed!=recommendation.Source ||
           source.Health!=RotationSourceHealth.Ready ||
           source.ReceivedAt==default || source.ReceivedAt>now ||
           now-source.ReceivedAt>TimeSpan.FromMilliseconds(900))
        {reason="UNVERIFIED SOURCE";return null;}
        if(state.Transport!=Knowledge.Known || state.CapturedAt>now ||
           now-state.CapturedAt>TimeSpan.FromMilliseconds(900))
        {reason="STALE GAMESTATE";return null;}
        if(recommendation.At>now || now-recommendation.At>TimeSpan.FromMilliseconds(900))
        {reason="STALE RECOMMENDATION";return null;}
        if(recommendation.SpellId<=0 || !bindings.TryGetValue(recommendation.SpellId,out var key))
        {reason="NO KEY BINDING";return null;}
        if(lastSource==recommendation.Source && lastEpoch==source.Epoch &&
           recommendation.At<=lastSnapshotAt)
        {reason="FRAME ALREADY HANDLED";return null;}
        if(lastIssuedAt!=default && now-lastIssuedAt<TimeSpan.FromMilliseconds(200))
        {reason="RATE LIMIT";return null;}
        lastSource=recommendation.Source;
        lastEpoch=source.Epoch;
        lastSnapshotAt=recommendation.At;
        lastIssuedAt=now;
        reason="PLANNED ONLY / NO INPUT";
        return new(recommendation.SpellId,key,recommendation.Source,source.Epoch,
            recommendation.At);
    }
}
