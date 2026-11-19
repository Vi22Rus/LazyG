using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Text.Json;

namespace LazyG.Desktop.Diagnostics;

// Safe, opt-in support archive writer. Never accepts arbitrary file paths/log text/pixels.
// Crash handler wiring and automation disarm are separate safety-critical integration work.
internal static class RotationSupportArchive
{
    internal sealed record SafeState(string Version, string? Source, string SourceHealth,
        string? BlockReason, string? Client, string? Profile, long RgbMissing,
        long RgbStale, int UnknownRules, int BlockedRules);
    private static readonly JsonSerializerOptions JsonOptions=new() { WriteIndented=true };
    public static string Create(string directory,SafeState state,string reason,
        bool fatal=false,DateTimeOffset? at=null)
    {
        // User-generated fields are deliberately not exported verbatim.
        var now=at??DateTimeOffset.UtcNow;
        var id=Guid.NewGuid().ToString("N");
        Directory.CreateDirectory(directory);
        string path=Path.Combine(directory,
            "LazyG-support-"+now.ToUniversalTime().ToString("yyyyMMdd-HHmmss")+"-"+id[..8]+".zip");
        using var output=new FileStream(path,FileMode.CreateNew,FileAccess.Write,FileShare.None);
        using var zip=new ZipArchive(output,ZipArchiveMode.Create,leaveOpen:false);
        void Add(string name,object data)
        {
            using var writer=new StreamWriter(zip.CreateEntry(name,CompressionLevel.Optimal).Open());
            writer.Write(JsonSerializer.Serialize(data,JsonOptions));
        }
        Add("manifest.json",new { Schema=1,CreatedUtc=now.ToUniversalTime(),Mode=fatal?"fatal":"manual",
            Note="Review locally before sharing; never uploaded automatically." });
        Add("crash.json",new { Fatal=fatal,ReasonCode=NormalizeReason(reason),CorrelationId=id });
        Add("rgb-health.json",new { Missing=Math.Max(0,state.RgbMissing),Stale=Math.Max(0,state.RgbStale) });
        Add("rotation-state.json",new { Source=SafeSource(state.Source),Health=NormalizeHealth(state.SourceHealth),
            BlockReason=NormalizeReason(state.BlockReason),UnknownRules=Math.Max(0,state.UnknownRules),
            BlockedRules=Math.Max(0,state.BlockedRules) });
        Add("settings-summary.json",new { ValuesExcluded=true,OverridesExcluded=true });
        Add("compatibility.json",new { Client=state.Client=="forever"?"forever":"unknown",
            ProfileIdentifiersExcluded=true });
        Add("build.json",new { Version=SafeVersion(state.Version) });
        return path;
    }
    private static string SafeSource(string? source) => source is "Internal" or "Hekili" or "JustAC" ? source : "Unknown";
    private static string NormalizeHealth(string? health) => health switch {
        "Ready" or "NoRecommendation" or "Unavailable" or "Stale" or "Incompatible" or "AwaitingTransport" => health,
        _=>"Unknown"
    };
    private static string NormalizeReason(string? reason) => reason switch {
        "RgbLost" or "StaleFrame" or "InvalidProtocol" or "ProviderUnavailable" or
        "ProviderIncompatible" or "NoRecommendation" or "UnknownSignal" or
        "UnhandledException" or "ManualSupport" => reason,
        _=>"Unspecified"
    };
    private static string SafeVersion(string? version) =>
        !string.IsNullOrWhiteSpace(version) && version.Length<=32 &&
        System.Text.RegularExpressions.Regex.IsMatch(version,@"^[0-9A-Za-z.\-]+$")
            ? version:"unknown";
}
