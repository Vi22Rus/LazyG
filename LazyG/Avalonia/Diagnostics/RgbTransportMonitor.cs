using System;
using System.Text.Json;

namespace LazyG.Desktop.Diagnostics;

// The RGB diagnostic layer is separate from GameState and XML authorization.
// No screenshots, player names, keyboard data, secrets, or pixel buffers are saved.
internal sealed record RgbSample(
    DateTimeOffset At, double CaptureMilliseconds, bool Foreground,
    bool V2, bool V3, byte? V3Sequence, bool Curve,
    bool LgdEnabled, bool Lgd, byte? LgdSequence,
    bool LgcEnabled, bool Lgc, byte? LgcSequence,
    string FailureCategory);

internal sealed class RgbChannelHealth
{
    public string Name { get; }
    public string Status { get; private set; }="NotObserved";
    public string Reason { get; private set; }="Startup";
    public long Seen { get; private set; }
    public long Advanced { get; private set; }
    public long Frozen { get; private set; }
    public long Lost { get; private set; }
    public long Recovered { get; private set; }
    public DateTimeOffset LastSeenAt { get; private set; }
    public DateTimeOffset LastAdvancedAt { get; private set; }
    public byte? Sequence { get; private set; }
    private bool everLive;
    private bool awaitingRecovery;
    public RgbChannelHealth(string name) => Name=name;
    public void Update(DateTimeOffset now, bool enabled, bool baseReady,
        bool found, byte? sequence, TimeSpan staleAfter)
    {
        if(!enabled) { Change("Disabled","OptInOff"); Sequence=null;return; }
        if(!baseReady) { Change("Unavailable","BaseIdentityMissing"); Sequence=null;return; }
        if(!found || !sequence.HasValue)
        {
            Change("Missing","StripNotFoundOrInvalid");
            Sequence=null;
            return;
        }
        Seen++;
        LastSeenAt=now;
        if(Sequence==sequence)
        {
            if(now<LastAdvancedAt || now-LastAdvancedAt>staleAfter)
            {
                if(Status!="Stale") Frozen++;
                Change("Stale","SequenceNotAdvancing");
            }
            return;
        }
        Sequence=sequence;
        LastAdvancedAt=now;
        Advanced++;
        if(awaitingRecovery && everLive) { Recovered++; awaitingRecovery=false; }
        everLive=true;
        Change("Live","NewSequence");
    }
    private void Change(string next, string reason)
    {
        if(next==Status && reason==Reason)return;
        if(everLive && Status=="Live" && next!="Live" ||
           everLive && Status=="Stale" && next!="Stale" && !awaitingRecovery)
        {
            Lost++;
            awaitingRecovery=true;
        }
        Status=next;
        Reason=reason;
    }
    public void Reset()
    {
        Status="NotObserved";Reason="Startup";
        Seen=Advanced=Frozen=Lost=Recovered=0;
        LastSeenAt=LastAdvancedAt=default;
        Sequence=null;everLive=false;awaitingRecovery=false;
    }
    public object Report(DateTimeOffset now) => new {
        Name, Status, Reason, Seen, Advanced, Frozen, Lost, Recovered,
        Sequence, LastSeenAt=LastSeenAt==default?null:(object)LastSeenAt,
        LastAdvancedAt=LastAdvancedAt==default?null:(object)LastAdvancedAt,
        AgeMilliseconds=LastAdvancedAt==default?-1:
            Math.Max(0,(long)(now-LastAdvancedAt).TotalMilliseconds)
    };
}

// Only explicit, safely decoded status fields. Missing values stay null or "Unknown".
internal sealed record RgbDecodedView(
    byte? V2ClassId, byte? V2RaceId, byte? V2Level,
    byte? V2SpecIndex, byte? V2CombatFlagBits,
    int? V3ProfileHash, byte? V3PlayerHealthRaw,
    byte? V3TargetHealthRaw, int? V3PowerRaw,
    byte? V3CombatFlagBits, byte? V3TargetFlagBits,
    string? CurvePlayerHealthBand, string? CurveTargetHealthBand,
    string? CurveResourceBand,
    int? LgdSpellId, string? LgdLearned, string? LgdUsable,
    string? LgdCooldownActive, string? LgdGcdActive,
    int? LgcSpellId, string? LgcSpellActive, string? LgcSpellOnGcd,
    string? LgcGcd29515Active, string? LgcGcd29515OnGcd);

internal sealed class RgbTransportMonitor
{
    public const string Schema="lazy-rgb-diagnostics-v1";
    public static readonly TimeSpan StaleAfter=TimeSpan.FromMilliseconds(1500);
    public RgbChannelHealth V3 { get; }=new("RGBv3_CRC");
    public RgbChannelHealth LGD { get; }=new("LGD_Spell");
    public RgbChannelHealth LGC { get; }=new("LGC_Cooldown");
    private long samples, foregroundFrames, baseFrames, curveFrames, captureFailures;
    private double totalCaptureMs, maxCaptureMs;
    private DateTimeOffset firstAt, lastAt;
    private string captureStatus="NotObserved", captureReason="Startup";
    private bool lastCurve, lastBase;
    private RgbDecodedView? decoded;
    public void SetDecoded(RgbDecodedView? value)=>decoded=value;
    public long Samples=>samples;
    public string CaptureStatus=>captureStatus;
    public string CaptureReason=>captureReason;
    public long BaseFrames=>baseFrames;
    public long CurveFrames=>curveFrames;

    public void Accept(RgbSample sample)
    {
        if(samples>0 && sample.At<lastAt)
        {
            // Monotonicity failure cannot extend the validity of a prior packet.
            Reset();
        }
        if(samples==0)firstAt=sample.At;
        samples++;
        lastAt=sample.At;
        totalCaptureMs+=Math.Max(0,sample.CaptureMilliseconds);
        maxCaptureMs=Math.Max(maxCaptureMs,Math.Max(0,sample.CaptureMilliseconds));
        if(sample.Foreground)foregroundFrames++;else captureFailures++;
        if(sample.Foreground && sample.V2)baseFrames++;
        if(sample.Foreground && sample.V2 && sample.V3 && sample.Curve)curveFrames++;
        lastCurve=sample.Foreground && sample.V2 && sample.V3 && sample.Curve;
        lastBase=sample.Foreground && sample.V2;
        captureStatus=!sample.Foreground?"Unavailable":!sample.V2?"NoBase":"Live";
        captureReason=sample.FailureCategory;
        V3.Update(sample.At,true,lastBase,
            sample.V3,sample.V3Sequence,StaleAfter);
        LGD.Update(sample.At,sample.LgdEnabled,lastBase,
            sample.Lgd,sample.LgdSequence,StaleAfter);
        LGC.Update(sample.At,sample.LgcEnabled,lastBase,
            sample.Lgc,sample.LgcSequence,StaleAfter);
    }
    public string Summary() =>
        $"RGBMON capture={captureStatus} v2={(lastBase?"OK":"Unavailable")}"+
        $" v3={V3.Status} curve={(lastCurve?"OK":"Unavailable")}"+
        $" LGD={LGD.Status} LGC={LGC.Status}"+
        $" frames={samples} base={baseFrames}"+
        $" crc={V3.Advanced} curveFrames={curveFrames}"+
        $" LGC(recovery={LGC.Recovered},stale={LGC.Frozen},lost={LGC.Lost})";
    public string ExportJson() => JsonSerializer.Serialize(new {
        Schema, GeneratedAt=lastAt, FirstAt=firstAt,
        SampleCount=samples, ForegroundFrames=foregroundFrames,
        BaseV2Frames=baseFrames, CurveFrames=curveFrames,
        CaptureFailures=captureFailures,
        CaptureStatus=captureStatus,CaptureReason=captureReason,
        LatestDecoded=decoded,
        MeanCaptureMilliseconds=samples==0?0:Math.Round(totalCaptureMs/samples,2),
        MaxCaptureMilliseconds=Math.Round(maxCaptureMs,2),
        Channels=new[]{V3.Report(lastAt),LGD.Report(lastAt),LGC.Report(lastAt)},
        Safety="Diagnostic read-only. No spell readiness, no GCD/CD milliseconds, no input."
    },new JsonSerializerOptions { WriteIndented=true });
    public void Reset()
    {
        samples=foregroundFrames=baseFrames=curveFrames=captureFailures=0;
        totalCaptureMs=maxCaptureMs=0;
        firstAt=lastAt=default;
        captureStatus="NotObserved";captureReason="Startup";
        lastCurve=lastBase=false;
        decoded=null;
        // Channel instances must also reset counters rather than retaining a
        // previous session's last-valid frame.
        V3.Reset();LGD.Reset();LGC.Reset();
    }
}
