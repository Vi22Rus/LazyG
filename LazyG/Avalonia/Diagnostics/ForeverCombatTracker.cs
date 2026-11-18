using System;
using System.Collections.Generic;
using LazyG.Desktop.Engine;

namespace LazyG.Desktop.Diagnostics;

// Data model for future verified diagnostic transport. No live capture yet.
// Events are observations, NOT evidence of auras being present or a spell ready.
internal enum ForeverCombatEventKind
{
    PlayerCastSucceeded, TargetCastStarted, TargetCastStopped,
    TargetCastSucceeded, PlayerAuraChanged, TargetAuraChanged, TargetChanged
}
internal sealed record ForeverCombatEvent(
    ForeverCombatEventKind Kind, DateTimeOffset At, int? PlainSpellId = null);

internal sealed record ForeverCombatSnapshot(
    int TargetEpoch,
    Observed<bool> TargetCasting,
    Observed<int> TargetCastSpellId,
    Observed<int> PlayerLastSucceededSpellId,
    DateTimeOffset? PlayerLastSucceededAt,
    DateTimeOffset? PlayerAuraChangedAt,
    DateTimeOffset? TargetAuraChangedAt);

internal sealed class ForeverCombatTracker
{
    private int epoch;
    private Observed<bool> casting=Observed<bool>.Missing();
    private Observed<int> castSpell=Observed<int>.Missing();
    private Observed<int> lastPlayerSpell=Observed<int>.Missing();
    private DateTimeOffset? lastPlayerAt,playerAuraAt,targetAuraAt;
    private DateTimeOffset? latest;
    private static bool SpellValid(int? id) => id.HasValue && id.Value>0 && id.Value<=16777215;

    // Reject out-of-order observations to avoid restoring an old target cast.
    public bool Apply(ForeverCombatEvent observation)
    {
        if (latest.HasValue && observation.At<latest.Value) return false;
        latest=observation.At;
        switch(observation.Kind)
        {
            case ForeverCombatEventKind.TargetChanged:
                epoch++;
                casting=Observed<bool>.Missing();
                castSpell=Observed<int>.Missing();
                targetAuraAt=null;
                break;
            case ForeverCombatEventKind.TargetCastStarted:
                casting=Observed<bool>.Known(true,observation.At);
                castSpell=SpellValid(observation.PlainSpellId)
                    ? Observed<int>.Known(observation.PlainSpellId!.Value,observation.At)
                    : Observed<int>.Missing();
                break;
            case ForeverCombatEventKind.TargetCastStopped:
            case ForeverCombatEventKind.TargetCastSucceeded:
                casting=Observed<bool>.Known(false,observation.At);
                castSpell=Observed<int>.Missing();
                break;
            case ForeverCombatEventKind.PlayerCastSucceeded:
                lastPlayerSpell=SpellValid(observation.PlainSpellId)
                    ? Observed<int>.Known(observation.PlainSpellId!.Value,observation.At)
                    : Observed<int>.Missing();
                lastPlayerAt=observation.At;
                break;
            case ForeverCombatEventKind.PlayerAuraChanged:
                playerAuraAt=observation.At;
                break;
            case ForeverCombatEventKind.TargetAuraChanged:
                targetAuraAt=observation.At;
                break;
        }
        return true;
    }

    public ForeverCombatSnapshot Snapshot(DateTimeOffset now, TimeSpan ttl)
    {
        bool valid(DateTimeOffset? at) => at.HasValue && at.Value<=now && now-at.Value<=ttl;
        return new ForeverCombatSnapshot(
            epoch, casting.At(now,ttl), castSpell.At(now,ttl),
            lastPlayerSpell.At(now,ttl),
            valid(lastPlayerAt)?lastPlayerAt:null,
            valid(playerAuraAt)?playerAuraAt:null,
            valid(targetAuraAt)?targetAuraAt:null);
    }
}
