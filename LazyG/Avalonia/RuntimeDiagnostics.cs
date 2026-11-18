using System;
using System.Collections.Generic;
using System.Linq;

namespace LazyG.Desktop;

// In-memory debug history. Never stores pixels, character names, credentials or images.
internal static class RuntimeDiagnostics
{
    private static readonly object Sync = new();
    private static readonly Queue<string> Events = new();
    private const int Limit = 150;
    public static void Add(string category, string message)
    {
        string record = DateTime.Now.ToString("HH:mm:ss") + " [" + category + "] " + message;
        lock (Sync)
        {
            Events.Enqueue(record);
            while (Events.Count > Limit) Events.Dequeue();
        }
    }
    public static string Snapshot()
    {
        lock (Sync) return string.Join(Environment.NewLine, Events.Reverse());
    }
    public static void Clear()
    {
        lock (Sync) Events.Clear();
        Add("LOG", "In-memory diagnostics cleared");
    }
}