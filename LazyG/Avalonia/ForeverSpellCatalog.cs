using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text.Json;
using Avalonia;
using Avalonia.Media;
using Bitmap = Avalonia.Media.Imaging.Bitmap;
using CroppedBitmap = Avalonia.Media.Imaging.CroppedBitmap;

namespace LazyG.Desktop;

// Data from the user-supplied LazyG_Icons.7z, client-specific: WoW Forever only.
// No web requests, and no confusion between same SpellID on different classes.
internal sealed record ForeverSpell(
    string ClassName, int SpellId, string NameRu, string NameEn,
    int IconId, int AtlasIndex, bool GenericAttackFallback)
{
    public string DisplayName(string language) => language.Equals("ru",StringComparison.OrdinalIgnoreCase) ? NameRu : NameEn;
}

internal static class ForeverSpellCatalog
{
    private static readonly Lazy<IReadOnlyList<ForeverSpell>> Catalog = new(LoadCatalog);
    private static readonly Lazy<Bitmap?> Atlas = new(LoadAtlas);
    private static readonly Lazy<Dictionary<(string ClassName,int SpellId),ForeverSpell>> ByClassAndId =
        new(() => Catalog.Value.GroupBy(s => (s.ClassName.ToLowerInvariant(),s.SpellId))
              .ToDictionary(g => g.Key,g => g.First()));
    private const int Columns=20, IconSize=56;
    public static int Count => Catalog.Value.Count;
    public static int FallbackCount => Catalog.Value.Count(x=>x.GenericAttackFallback);
    public static IEnumerable<ForeverSpell> ForClass(string className) =>
        Catalog.Value.Where(x=>x.ClassName.Equals(className,StringComparison.OrdinalIgnoreCase));
    public static IReadOnlyList<ForeverSpell> All => Catalog.Value;
    public static ForeverSpell? Find(string className,int spellId)
    {
        // Per-class identity is intentional: e.g. auto-attack icons differ.
        if(ByClassAndId.Value.TryGetValue((className.ToLowerInvariant(),spellId),out var value))
            return value;
        return ByClassAndId.Value.TryGetValue(("general",spellId),out value) ? value : null;
    }
    public static CroppedBitmap? Icon(ForeverSpell entry)
    {
        var atlas=Atlas.Value;
        if(atlas is null)return null;
        int i=entry.AtlasIndex;
        return new CroppedBitmap(atlas,new PixelRect((i%Columns)*IconSize,(i/Columns)*IconSize,IconSize,IconSize));
    }

    private static IReadOnlyList<ForeverSpell> LoadCatalog()
    {
        using var stream=typeof(ForeverSpellCatalog).Assembly.GetManifestResourceStream("LazyG.ForeverSpellCatalog")
            ?? throw new InvalidDataException("Forever spell catalog resource missing");
        using var reader=new StreamReader(stream);
        byte[] compressed=Convert.FromBase64String(reader.ReadToEnd().Trim());
        using var input=new GZipStream(new MemoryStream(compressed),CompressionMode.Decompress);
        using var doc=JsonDocument.Parse(input);
        if(doc.RootElement.GetProperty("client").GetString()!="forever" ||
           doc.RootElement.GetProperty("format").GetInt32()!=1 ||
           doc.RootElement.GetProperty("iconSize").GetInt32()!=IconSize)
            throw new InvalidDataException("Unexpected Forever catalog version");
        var rows=new List<ForeverSpell>(512);
        foreach(var row in doc.RootElement.GetProperty("rows").EnumerateArray())
        {
            var v=row.EnumerateArray().ToArray();
            rows.Add(new ForeverSpell(v[0].GetString()!,v[1].GetInt32(),v[2].GetString()!,
                v[3].GetString()!,v[4].GetInt32(),v[5].GetInt32(),v[6].GetInt32()!=0));
        }
        return rows;
    }
    private static Bitmap? LoadAtlas()
    {
        try
        {
            using var stream=typeof(ForeverSpellCatalog).Assembly.GetManifestResourceStream("LazyG.ForeverSpellAtlas");
            if(stream is null)return null;
            using var reader=new StreamReader(stream);
            using var image=new MemoryStream(Convert.FromBase64String(reader.ReadToEnd().Trim()));
            return new Bitmap(image);
        }
        catch(Exception e)
        {
            RuntimeDiagnostics.Add("SPELLS","Atlas unavailable: "+e.GetType().Name);
            return null;
        }
    }
}
