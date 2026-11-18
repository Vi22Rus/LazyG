using System;
using System.Collections.Generic;
using System.IO;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Media;
using Avalonia.Media.Imaging;
using Control = Avalonia.Controls.Control;
using Bitmap = Avalonia.Media.Imaging.Bitmap;
using Image = Avalonia.Controls.Image;

namespace LazyG.Desktop;
internal static class IconPack
{
    private const int Tile = 36;
    // Artwork positions are based on verified Blizzard-style specialization icons
    // extracted from the user-provided reference executable, in class/spec order.
    private static readonly string[] Keys =
    [
        "Warrior_Arms","Warrior_Fury","Warrior_Protection",
        "Paladin_Holy","Paladin_Protection","Paladin_Retribution",
        "Hunter_BeastMastery","Hunter_Marksmanship","Hunter_Survival",
        "Rogue_Assassination","Rogue_Combat","Rogue_Subtlety",
        "Priest_Discipline","Priest_Holy","Priest_Shadow",
        "Shaman_Elemental","Shaman_Enhancement","Shaman_Restoration",
        "Mage_Arcane","Mage_Fire","Mage_Frost",
        "Warlock_Affliction","Warlock_Demonology","Warlock_Destruction",
        "Druid_Balance","Druid_Feral","Druid_Restoration"
    ];
    private static readonly Dictionary<string,int> Positions = new(StringComparer.OrdinalIgnoreCase);
    private static readonly Bitmap? Atlas;
    private static readonly Bitmap? ClassAtlas;
    private static readonly string[] ClassKeys = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid" };
    static IconPack()
    {
        for (int i=0;i<Keys.Length;i++) Positions[Keys[i]]=i;

        try
        {
            using var stream=typeof(IconPack).Assembly.GetManifestResourceStream("LazyG.IconPack");
            if(stream is not null)
            {
                using var reader=new StreamReader(stream);
                var encoded=reader.ReadToEnd().Trim();
                using var input=new MemoryStream(Convert.FromBase64String(encoded));
                Atlas=new Bitmap(input);
            }
        }
        catch(Exception) { Atlas=null; }
        try
        {
            using var stream=typeof(IconPack).Assembly.GetManifestResourceStream("LazyG.ClassIcons");
            if(stream is not null)
            {
                using var reader=new StreamReader(stream);
                using var input=new MemoryStream(Convert.FromBase64String(reader.ReadToEnd().Trim()));
                ClassAtlas=new Bitmap(input);
            }
        }
        catch(Exception) { ClassAtlas=null; }
    }
    public static Control Create(string key,int size)
    {
        int classIndex=Array.FindIndex(ClassKeys,k=>string.Equals(k,key,StringComparison.OrdinalIgnoreCase));
        if(ClassAtlas is not null && classIndex>=0)
        {
            var image=new CroppedBitmap(ClassAtlas,new PixelRect((classIndex%3)*Tile,(classIndex/3)*Tile,Tile,Tile));
            return new Image {Source=image,Width=size,Height=size,Stretch=Stretch.Fill};
        }
        if (Atlas is not null && Positions.TryGetValue(key,out int idx))
        {
            var clip=new CroppedBitmap(Atlas,new PixelRect((idx%3)*Tile,(idx/3)*Tile,Tile,Tile));
            return new Image {Source=clip,Width=size,Height=size,Stretch=Stretch.Fill};
        }
        return new TextBlock {Text=key.Length>0?key.Substring(0,1):"?",FontSize=size*.7,
            FontWeight=FontWeight.Bold,TextAlignment=TextAlignment.Center,
            VerticalAlignment=Avalonia.Layout.VerticalAlignment.Center,Foreground=Palette.Gold};
    }
}