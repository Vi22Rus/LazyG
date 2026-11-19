using System;
using LazyG.Desktop.Engine;

namespace LazyG.Desktop.Diagnostics;

// Diagnostic-only, NOT an authorization source. LGC carries booleans, never
// numerical remaining cooldown/GCD durations or permission to cast.
internal sealed record CooldownObservation(
    int SpellId,
    Observed<bool> SpellCooldownActive,
    Observed<bool> SpellOnGcd,
    Observed<bool> Gcd29515Active,
    Observed<bool> Gcd29515OnGcd,
    DateTimeOffset LastNewFrameAt,
    Knowledge Transport)
{
    public static CooldownObservation Empty(Knowledge quality=Knowledge.Unknown) =>
        new(0,Observed<bool>.Missing(quality),Observed<bool>.Missing(quality),
            Observed<bool>.Missing(quality),Observed<bool>.Missing(quality),
            default,quality);
}

internal sealed class ForeverCooldownObserver
{
    public static readonly TimeSpan MaxFrameAge=TimeSpan.FromMilliseconds(1200);
    private CooldownRgbPacket? lastPacket;
    private DateTimeOffset lastNewFrameAt;
    private CooldownObservation current=CooldownObservation.Empty();
    public CooldownObservation Snapshot=>current;
    public int Recoveries { get; private set; }
    public string LastLossReason { get; private set; }="NotYetObserved";
    private bool hadValidObservation;
    private bool awaitingRecovery;

    public CooldownObservation Update(bool verifiedBaseIdentity,
        CooldownRgbPacket? packet,DateTimeOffset now)
    {
        // Missing base transport or LGC immediately invalidates prior data;
        // do not keep a former False when the game loses foreground.
        if(!verifiedBaseIdentity || packet is null)
        {
            Invalidate(!verifiedBaseIdentity?"BaseRgbIdentityLost":"LgcPacketMissing");
            return current;
        }
        if(lastPacket is not null && now<lastNewFrameAt)
        {
            Invalidate("CaptureClockReversed");
            return current;
        }
        if(lastPacket is not null && packet.Sequence==lastPacket.Sequence)
        {
            // A sequence byte may be reused only for an identical packet.
            // Different contents with the same sequence are ambiguous.
            if(packet!=lastPacket)
            {
                Invalidate("SameSequenceConflict");
                return current;
            }
            if(now-lastNewFrameAt>MaxFrameAge)
            {
                if(current.Transport!=Knowledge.Stale)
                    MarkLost("FrozenLgcSequence");
                current=CooldownObservation.Empty(Knowledge.Stale)
                    with { SpellId=packet.SpellId,LastNewFrameAt=lastNewFrameAt };
            }
            return current;
        }
        // If an old frame reappears with a different sequence following a
        // disconnect, it cannot inherit the previous known observation.
        if(awaitingRecovery)
        {
            Recoveries++;
            awaitingRecovery=false;
        }
        hadValidObservation=true;
        lastPacket=packet;
        lastNewFrameAt=now;
        current=new CooldownObservation(packet.SpellId,
            ForeverSpellProbeCodec.Observe(packet.SpellActive,now),
            ForeverSpellProbeCodec.Observe(packet.SpellOnGcd,now),
            ForeverSpellProbeCodec.Observe(packet.Gcd29515Active,now),
            ForeverSpellProbeCodec.Observe(packet.Gcd29515OnGcd,now),
            now,Knowledge.Known);
        return current;
    }

    private void MarkLost(string reason)
    {
        LastLossReason=reason;
        if(hadValidObservation)awaitingRecovery=true;
    }
    private void Invalidate(string reason)
    {
        if(current.Transport!=Knowledge.Unknown || lastPacket is not null)
            MarkLost(reason);
        lastPacket=null;
        lastNewFrameAt=default;
        current=CooldownObservation.Empty();
    }
    public void Reset()
    {
        lastPacket=null;
        lastNewFrameAt=default;
        current=CooldownObservation.Empty();
        Recoveries=0;
        hadValidObservation=false;
        awaitingRecovery=false;
        LastLossReason="ManualReset";
    }

    public string Describe() => current.Transport switch
    {
        Knowledge.Stale=>"LGC STALE (sequence stopped; all states invalid) reason="+LastLossReason,
        Knowledge.Unknown=>"LGC unavailable (no verified fresh frame) reason="+LastLossReason,
        _=>$"LGC SpellID {current.SpellId} CD={Render(current.SpellCooldownActive)}"+
            $" onGCD={Render(current.SpellOnGcd)}"+
            $" GCD(29515)={Render(current.Gcd29515Active)}"+
            $" gcdOnGCD={Render(current.Gcd29515OnGcd)}"+
            $" recoveries={Recoveries} [read-only; numeric time Unknown; no cast permission]"
    };
    private static string Render(Observed<bool> value)=>value.Quality switch
    {
        Knowledge.Protected=>"Protected",
        Knowledge.Stale=>"Stale",
        Knowledge.Known=>value.Value==true?"True":"False",
        _=>"Unknown"
    };
}
