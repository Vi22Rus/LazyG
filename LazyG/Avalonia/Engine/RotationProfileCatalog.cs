using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;

namespace LazyG.Desktop.Engine;

// Explicit allowlist: absent profiles remain Unavailable, never clone another specialization.
internal static class RotationProfileCatalog
{
    private static readonly IReadOnlyDictionary<(string Class,string Spec,string Mode),string> Profiles=
        new Dictionary<(string,string,string),string> {
            [("paladin","retribution","PvP")]="LazyG.Forever.RetributionPvPExperimental",
            [("warrior","arms","PvE")]="LazyG.Forever.ArmsPvEExperimental",
            [("hunter","beast-mastery","PvE")]="LazyG.Forever.HunterBmPvEExperimental"
        };

    public static string Status(string classSlug,string specSlug,string mode) =>
        Profiles.ContainsKey((classSlug,specSlug,mode))?"Experimental (offline only)":"Unavailable";

    public static RotationProfileV2? Load(string classSlug,string specSlug,string mode)
    {
        if(!Profiles.TryGetValue((classSlug,specSlug,mode),out var resource))return null;
        using var stream=typeof(RotationProfileCatalog).Assembly.GetManifestResourceStream(resource)
            ?? throw new InvalidDataException("Missing embedded rotation "+resource);
        using var reader=new StreamReader(stream);
        return RotationXmlV2.Parse(reader.ReadToEnd());
    }
}
