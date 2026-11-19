using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using System.Text.Json;

namespace LazyG.Desktop.Engine;

// One independent observation ledger. An IOCTL success is NOT a WoW cast.
// The optional LGE UNIT_SPELLCAST_SUCCEEDED event is weaker than an effect
// confirmation. Never label absence of LGE as a failed cast.
internal sealed record RotationTraceEvent(long Id,DateTimeOffset At,string Kind,
    int? SpellId,string Detail,long? AttemptId=null,string? RuleId=null);
internal sealed class RotationExecutionTrace
{
    private readonly object sync=new();
    private readonly List<RotationTraceEvent> rows=new();
    private readonly int capacity;
    private long nextId;
    private bool recording;
    private string session="none";
    public RotationExecutionTrace(int capacity=5000)
    {
        if(capacity<10 || capacity>20000)throw new ArgumentOutOfRangeException(nameof(capacity));
        this.capacity=capacity;
    }
    public bool Recording {get {lock(sync)return recording;}}
    public void Start(DateTimeOffset at,string profile)
    {
        lock(sync)
        {
            rows.Clear();
            nextId=0;
            session=profile;
            recording=true;
            Append(at,"SESSION_START",null,profile);
        }
    }
    public void Stop(DateTimeOffset at,string reason)
    {
        lock(sync)
        {
            if(!recording)return;
            Append(at,"SESSION_STOP",null,reason);
            recording=false;
        }
    }
    private long Append(DateTimeOffset at,string kind,int? spellId,string detail,
        long? attempt=null,string? rule=null)
    {
        long id=++nextId;
        if(rows.Count==capacity)rows.RemoveAt(0);
        rows.Add(new(id,at,kind,spellId,detail,attempt,rule));
        return id;
    }
    public long Add(DateTimeOffset at,string kind,int? spellId,string detail,
        long? attempt=null,string? rule=null)
    {
        lock(sync)
            return recording?Append(at,kind,spellId,detail,attempt,rule):0;
    }
    public long Recommend(DateTimeOffset at,int spellId,string rule) =>
        Add(at,"XML_RECOMMENDED",spellId,"XML evaluation only",null,rule);
    public long Attempt(DateTimeOffset at,int spellId,string rule) =>
        Add(at,"HID_ATTEMPT",spellId,"Command authorized; no driver acknowledgement",null,rule);
    public void DriverResult(DateTimeOffset at,int spellId,long attempt,bool success,
        string diagnostic) =>
        Add(at,success?"HID_IO_COMPLETED":"HID_IO_FAILED",spellId,diagnostic,attempt);
    public void CastEvent(DateTimeOffset at,int spellId,bool playerConfirmed)
    {
        lock(sync)
        {
            if(!recording)return;
            // Temporal association is diagnostic, not causal attribution.
            var prior=rows.LastOrDefault(e=>e.Kind=="HID_IO_COMPLETED" &&
                e.At<=at && at-e.At<=TimeSpan.FromMilliseconds(1800));
            string detail=prior is null
                ?"Player event without preceding successful HID IO; source unknown"
                :prior.SpellId==spellId
                    ?"Observed player spellcast event same SpellID; causality/effect unverified"
                    :"Observed player spellcast event differs from preceding HID command";
            Append(at,playerConfirmed?"PLAYER_CAST_EVENT":"UNVERIFIED_CAST_EVENT",
                spellId,detail,prior?.AttemptId);
        }
    }
    public string Summary()
    {
        lock(sync)
        {
            int Count(string name)=>rows.Count(e=>e.Kind==name);
            return (recording?"RECORDING":"STOPPED")+" · XML="+Count("XML_RECOMMENDED")+
                " · input attempts="+Count("HID_ATTEMPT")+
                " · driver IO="+Count("HID_IO_COMPLETED")+
                " · IO failures="+Count("HID_IO_FAILED")+
                " · player events="+Count("PLAYER_CAST_EVENT")+
                " · NOTE: event ≠ proven automated cast";
        }
    }
    public string ExportJsonl()
    {
        lock(sync)
        {
            var lines=new List<string> {
                JsonSerializer.Serialize(new {schema=1,client="forever",
                    session,limitations="No input-to-cast attribution; LGE is optional and does not prove effect"})
            };
            lines.AddRange(rows.Select(row=>JsonSerializer.Serialize(row)));
            return string.Join("\n",lines)+"\n";
        }
    }
    public string ExportSummaryJson()
    {
        lock(sync)
        {
            int Total(string k)=>rows.Count(r=>r.Kind==k);
            var attempts=rows.Where(r=>r.Kind=="HID_ATTEMPT").ToArray();
            var outcomes=attempts.Select(a=>{
                var io=rows.FirstOrDefault(e=>e.AttemptId==a.Id &&
                    e.Kind is "HID_IO_COMPLETED" or "HID_IO_FAILED");
                var casts=rows.Where(e=>e.AttemptId==a.Id &&
                    e.Kind=="PLAYER_CAST_EVENT").ToArray();
                return new {
                    at=a.At,xmlSpellId=a.SpellId,rule=a.RuleId,
                    hidIo=io?.Kind??"NO_DRIVER_RESULT",
                    observedPlayerCast=casts.Select(c=>c.SpellId).ToArray(),
                    comparison=io is null?"NOT_SENT_OR_UNKNOWN":
                        io.Kind=="HID_IO_FAILED"?"DRIVER_FAILED":
                        casts.Length==0?"NO_OBSERVABLE_CAST":
                        casts.Any(c=>c.SpellId==a.SpellId)?
                            "SAME_SPELL_EVENT_CAUSALITY_UNPROVEN":
                            "DIFFERENT_SPELL_EVENT_CAUSALITY_UNPROVEN"
                };
            }).ToArray();
            return JsonSerializer.Serialize(new {
                schema=1,session,recording,at=DateTimeOffset.UtcNow,
                xmlRecommendations=Total("XML_RECOMMENDED"),
                hidAttempts=attempts.Length,
                driverCompleted=Total("HID_IO_COMPLETED"),
                driverFailed=Total("HID_IO_FAILED"),
                playerCastEvents=Total("PLAYER_CAST_EVENT"),
                limitation="WoW cast event does not establish that LazyG caused the action, and absence does not prove failure.",
                comparisons=outcomes
            },new JsonSerializerOptions{WriteIndented=true});
        }
    }
    public string ExportZip(string directory,string rgbJson,string runtimeLog,
        string? xmlAuditJson=null)
    {
        Directory.CreateDirectory(directory);
        string output=Path.Combine(directory,"LazyG-Diagnostic-"+
            DateTime.UtcNow.ToString("yyyyMMdd-HHmmss-fff")+".zip");
        using var file=File.Create(output);
        using var zip=new ZipArchive(file,ZipArchiveMode.Create);
        static void AddText(ZipArchive zip,string name,string text)
        {
            using var writer=new StreamWriter(zip.CreateEntry(name,
                CompressionLevel.Optimal).Open(),new UTF8Encoding(false));
            writer.Write(text);
        }
        AddText(zip,"rotation-trace.jsonl",ExportJsonl());
        AddText(zip,"rotation-comparison.json",ExportSummaryJson());
        AddText(zip,"rgb-health.json",rgbJson);
        AddText(zip,"events.txt",runtimeLog);
        if(xmlAuditJson is not null)AddText(zip,"xml-hunter-audit.json",xmlAuditJson);
        return output;
    }
}
