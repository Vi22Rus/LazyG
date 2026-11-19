using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;

namespace LazyG.Desktop.Engine;

// Per-profile override persistence. Data only: never mutates embedded XML.
internal static class RotationSettingsStore
{
    private const int MaxFileBytes=32768;
    private sealed record Document(int Schema, string Client, int ClassId, int SpecIndex,
        string Mode, Dictionary<string,int> Overrides);

    public static IReadOnlyDictionary<string,int> Load(string path,RotationProfileV2 profile)
    {
        if(!File.Exists(path))return new Dictionary<string,int>();
        if(new FileInfo(path).Length>MaxFileBytes)throw new InvalidDataException("Oversized settings file");
        try
        {
            var doc=JsonSerializer.Deserialize<Document>(File.ReadAllText(path))
                ?? throw new InvalidDataException("Missing settings");
            if(doc.Schema!=1 || doc.Client!=profile.Client || doc.ClassId!=profile.ClassId ||
                doc.SpecIndex!=profile.SpecIndex || doc.Mode!=profile.Mode || doc.Overrides is null)
                throw new InvalidDataException("Settings profile mismatch");
            // Reject unknown keys, illegal steps, or values before exposing them to the engine.
            RotationXmlV2.Resolve(profile,doc.Overrides);
            return new Dictionary<string,int>(doc.Overrides,StringComparer.Ordinal);
        }
        catch(JsonException ex) {throw new InvalidDataException("Malformed settings JSON",ex);}
        catch(FormatException ex) {throw new InvalidDataException("Invalid settings overrides",ex);}
    }

    public static void Save(string path,RotationProfileV2 profile,IReadOnlyDictionary<string,int> values)
    {
        var resolved=RotationXmlV2.Resolve(profile,values);
        var overrides=resolved.Where(kv=>kv.Value!=profile.Settings[kv.Key].Default)
            .ToDictionary(kv=>kv.Key,kv=>kv.Value,StringComparer.Ordinal);
        var doc=new Document(1,profile.Client,profile.ClassId,profile.SpecIndex,profile.Mode,overrides);
        byte[] bytes=JsonSerializer.SerializeToUtf8Bytes(doc,new JsonSerializerOptions { WriteIndented=true });
        if(bytes.Length>MaxFileBytes)throw new InvalidDataException("Settings file too large");
        string target=Path.GetFullPath(path);
        string dir=Path.GetDirectoryName(target)??throw new InvalidDataException("Directory missing");
        Directory.CreateDirectory(dir);
        string temp=target+".tmp."+Guid.NewGuid().ToString("N");
        try
        {
            using(var stream=new FileStream(temp,FileMode.CreateNew,FileAccess.Write,FileShare.None))
            {
                stream.Write(bytes);
                stream.Flush(true);
            }
            if(File.Exists(target))
            {
                // Atomic replacement and last-version backup on supported filesystems.
                File.Replace(temp,target,target+".bak",ignoreMetadataErrors:true);
            }
            else File.Move(temp,target);
        }
        finally {if(File.Exists(temp))File.Delete(temp);}
    }
    public static void Reset(string path,RotationProfileV2 profile) =>
        Save(path,profile,new Dictionary<string,int>());
}
