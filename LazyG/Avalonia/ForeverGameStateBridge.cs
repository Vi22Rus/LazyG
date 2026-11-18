using System;
using LazyGPrototype;
using LazyG.Desktop.Engine;

namespace LazyG.Desktop;

// Versioned adapter: maps ONLY verified RGB v2 fields; CRC v3 confirms
// transport integrity but does not make protected measurements available.
internal static class ForeverGameStateBridge
{
    public static GameState FromRgb(RgbPlayerState? state, bool crcOk, DateTimeOffset now,
        bool v3DeadConfirmed=false)
    {
        var empty=GameState.Empty(now);
        if(state is null)return empty;
        _ = crcOk; // Future extension: track v3 integrity in separate evidence, not RGB v2 transport.
        return empty with
        {
            CapturedAt=now,
            Transport=Knowledge.Known, // RGB v2 validator already checked markers/checksum; v3 CRC is independent.
            ClassId=Observed<int>.Known(state.ClassId,now),
            RaceId=Observed<int>.Known(state.RaceId,now),
            Level=Observed<int>.Known(state.Level,now),
            SpecIndex=state.SpecIndex>0
                ?Observed<int>.Known(state.SpecIndex,now):Observed<int>.Missing(),
            InCombat=Observed<bool>.Known(state.InCombat,now),
            TargetExists=state.TargetExists
                ?Observed<bool>.Known(true,now):Observed<bool>.Missing(),
            TargetHostile=state.TargetExists && state.TargetHostile
                ?Observed<bool>.Known(true,now):Observed<bool>.Missing(),
            TargetAlive=TargetLifeDecoder.Alive(state.TargetExists,state.TargetAlive,
                crcOk && v3DeadConfirmed,now),
        };
    }
    public static string Diagnostic(GameState game)
    {
        static string Show<T>(Observed<T> x) where T:struct =>
            x.Quality==Knowledge.Known?x.Value!.ToString()??"Unknown":x.Quality.ToString();
        return "GameState Forever [transport "+game.Transport+"]"+
            " · class "+Show(game.ClassId)+
            " · spec "+Show(game.SpecIndex)+
            " · combat "+Show(game.InCombat)+
            " · target "+Show(game.TargetExists)+
            " · hostile "+Show(game.TargetHostile)+
            " · alive "+Show(game.TargetAlive)+
            " · attackGate "+ConditionEvaluator.AttackTarget(game)+
            " · HP "+Show(game.PlayerHealthPercent)+
            " · power "+Show(game.PowerPercent)+
            " · GCD "+Show(game.GcdRemainingMilliseconds)+
            " · SpellReady "+ConditionEvaluator.SpellReady(game,1130);
    }
}
