using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Xml;
using System.Xml.Linq;

namespace LazyG.Desktop.Engine;

// v2 is independent of legacy diagnostic XML v1 and cannot send input.
internal enum RotationSourceId { Internal = 1, Hekili = 2, JustAC = 3 }
internal enum RotationSourceHealth { AwaitingTransport, Ready, NoRecommendation, Unavailable, Stale, Incompatible }
internal sealed record RotationRecommendation(RotationSourceId Source, int SpellId, int Priority, string RuleId, DateTimeOffset At);
internal sealed record RotationSourceSnapshot(RotationSourceId? Confirmed, RotationSourceHealth Health,
    long Epoch, uint Sequence, DateTimeOffset ReceivedAt, RotationRecommendation? Recommendation, string Reason);

internal sealed class RotationSourceManager
{
    private readonly TimeSpan _maxAge;
    private bool _hasWatermark;
    private long _lastEpoch;
    private uint _lastSequence;
    private RotationSourceId _lastSource;
    private RotationSourceSnapshot _state = new(null,RotationSourceHealth.AwaitingTransport,0,0,default,null,"Source RGB not implemented");
    public RotationSourceManager(TimeSpan? maxAge=null) => _maxAge=maxAge ?? TimeSpan.FromMilliseconds(900);
    public RotationSourceSnapshot Snapshot(DateTimeOffset now)
    {
        if (_state.Confirmed is null || _state.ReceivedAt==default) return _state with { Recommendation=null };
        if (now<_state.ReceivedAt || now-_state.ReceivedAt>_maxAge)
            return _state with { Health=RotationSourceHealth.Stale, Recommendation=null, Reason="Source frame expired" };
        return _state;
    }
    public void Disconnect(string reason) =>
        _state=new(null,RotationSourceHealth.Unavailable,_state.Epoch,_state.Sequence,default,null,reason);
    // Contract for FUTURE verified SRC/REC decoder; does not read existing v2/v3/Curve/LGD/LGC frames.
    public bool Accept(RotationSourceId source, bool compatible, bool providerReady,
        long epoch, uint sequence, int? spellId, DateTimeOffset receivedAt)
    {
        if (!Enum.IsDefined(source) || epoch<0 || receivedAt==default) { Disconnect("Invalid provider metadata"); return false; }
        // Keep the high-water mark even after disconnection: a stale duplicate
        // cannot re-authorize a source just because Confirmed was cleared.
        if (_hasWatermark && (epoch<_lastEpoch ||
            (epoch==_lastEpoch && (source!=_lastSource || sequence<=_lastSequence))))
        {
            Disconnect("Replay, nonmonotonic sequence or unconfirmed source change");
            return false;
        }
        _hasWatermark=true;
        _lastEpoch=epoch;
        _lastSequence=sequence;
        _lastSource=source;
        var health=!compatible?RotationSourceHealth.Incompatible:
            !providerReady?RotationSourceHealth.Unavailable:
            spellId is null && source!=RotationSourceId.Internal?RotationSourceHealth.NoRecommendation:
            RotationSourceHealth.Ready;
        // Recommendations never carry over across source, epoch or missing provider state.
        RotationRecommendation? rec=null;
        if (health==RotationSourceHealth.Ready && source!=RotationSourceId.Internal &&
            spellId is >0 and <=16777215)
            rec=new(source,spellId.Value,0,"external",receivedAt);
        else if (spellId is not null && source!=RotationSourceId.Internal)
            health=RotationSourceHealth.Unavailable;
        _state=new(source,health,epoch,sequence,receivedAt,rec,
            health==RotationSourceHealth.Ready?"Ready":health.ToString());
        return health is RotationSourceHealth.Ready or RotationSourceHealth.NoRecommendation;
    }
    public bool CanUseInternal(DateTimeOffset now) =>
        Snapshot(now) is { Confirmed:RotationSourceId.Internal, Health:RotationSourceHealth.Ready };
    public RotationRecommendation? ExternalRecommendation(DateTimeOffset now) =>
        Snapshot(now) is { Health:RotationSourceHealth.Ready, Confirmed:RotationSourceId.Hekili or RotationSourceId.JustAC } s
            ? s.Recommendation : null;
}

internal enum RotationSettingType { Boolean, Integer }
internal sealed record RotationSetting(string Id, RotationSettingType Type, string Unit, int Default,
    int Min, int Max, int Step, string Tier, string Group, string LabelRu, string LabelEn,
    string DescriptionRu="", string DescriptionEn="", int IconSpellId=0,
    string? ExclusiveGroup=null, string? Parent=null);
internal sealed record RotationCondition(string Signal, string Compare, string? SettingRef, int? Constant, string? WhenEnabled, int? AuraSpellId = null, IReadOnlyList<int>? AuraRanks = null);
internal sealed record RotationRuleV2(string Id, int Priority, int SpellId,
    string? EnabledBy, IReadOnlyList<RotationCondition> Conditions);
internal sealed record RotationProfileV2(string Client, int ClassId, int SpecIndex, string Mode,
    IReadOnlyDictionary<string,RotationSetting> Settings, IReadOnlyList<RotationRuleV2> Rules);
internal sealed record RotationRuleTrace(string RuleId, int SpellId, Truth Outcome, string Reason);
internal sealed record RotationEvaluation(RotationRecommendation? Recommendation,
    IReadOnlyList<RotationRuleTrace> Trace, string BlockReason);

// Shared-CD preferences are a user choice, NOT proof the spells have separate
// cooldowns in game. Persist every change atomically across all profile tabs.
internal static class RotationSettingsExclusivity
{
    public static IReadOnlyDictionary<string,int> Apply(RotationProfileV2 profile,
        IReadOnlyDictionary<string,int> overrides,string settingId,int newValue)
    {
        if(!profile.Settings.TryGetValue(settingId,out var setting))
            throw new FormatException("Unknown setting");
        var values=new Dictionary<string,int>(overrides,StringComparer.Ordinal);
        if(newValue==setting.Default)values.Remove(settingId);
        else values[settingId]=newValue;
        if(newValue==1 && setting.ExclusiveGroup is not null)
            foreach(var other in profile.Settings.Values.Where(x=>
                x.Id!=settingId && x.ExclusiveGroup==setting.ExclusiveGroup))
            {
                if(other.Default==0)values.Remove(other.Id);
                else values[other.Id]=0;
            }
        RotationXmlV2.Resolve(profile,values);
        return values;
    }
}

internal static class RotationXmlV2
{
    private const int MaxChars=65536;
    private static string Required(XElement e,string name) =>
        (string?)e.Attribute(name) is { Length: >0 } value ? value : throw new FormatException("Missing "+name);
    private static int Number(XElement e,string name) =>
        int.TryParse(Required(e,name),NumberStyles.None,CultureInfo.InvariantCulture,out int x)
            ? x : throw new FormatException("Invalid "+name);
    private static void Attributes(XElement e,params string[] allowed)
    {
        if(e.Attributes().Any(a=>!allowed.Contains(a.Name.LocalName) || a.Name.NamespaceName.Length!=0))
            throw new FormatException("Unknown XML attribute in "+e.Name);
    }
    public static RotationProfileV2 Parse(string xml)
    {
        if(string.IsNullOrWhiteSpace(xml) || xml.Length>MaxChars)throw new FormatException("XML size");
        try
        {
            using var reader=XmlReader.Create(new StringReader(xml),new XmlReaderSettings {
                DtdProcessing=DtdProcessing.Prohibit,XmlResolver=null,MaxCharactersInDocument=MaxChars,
                IgnoreWhitespace=true,IgnoreComments=true
            });
            var root=XDocument.Load(reader).Root ?? throw new FormatException("Missing root");
            if(root.Name!="Rotation" || Required(root,"version")!="2")throw new FormatException("Requires Rotation v2");
            Attributes(root,"version","client","classId","specIndex","mode");
            var client=Required(root,"client");
            if(client!="forever")throw new FormatException("Unsupported client");
            int classId=Number(root,"classId"),specIndex=Number(root,"specIndex");
            if(classId is <1 or >13 || specIndex is <1 or >4)throw new FormatException("Profile identity");
            var mode=Required(root,"mode");
            if(mode is not ("PvE" or "PvP"))throw new FormatException("Mode");
            var children=root.Elements().ToArray();
            if(children.Length!=2 || children[0].Name!="Settings" || children[1].Name!="Rules")
                throw new FormatException("Requires Settings then Rules");
            Attributes(children[0]); Attributes(children[1]);
            var settings=new Dictionary<string,RotationSetting>(StringComparer.Ordinal);
            foreach(var el in children[0].Elements())
            {
                if(el.Name!="Setting" || el.HasElements)throw new FormatException("Setting element");
                Attributes(el,"id","type","unit","default","min","max","step","tier","group","ru","en",
                    "descriptionRu","descriptionEn","iconSpellId","exclusiveGroup","parent");
                var id=Required(el,"id");
                if(!System.Text.RegularExpressions.Regex.IsMatch(id,@"^[a-z][A-Za-z0-9]{0,63}$"))
                    throw new FormatException("Setting id");
                var type=Required(el,"type") switch {
                    "bool"=>RotationSettingType.Boolean,"int"=>RotationSettingType.Integer,
                    _=>throw new FormatException("Setting type")
                };
                int min=Number(el,"min"),max=Number(el,"max"),step=Number(el,"step"),def=Number(el,"default");
                if(min<0 || max>100000 || min>max || step<1 || def<min || def>max ||
                   (def-min)%step!=0 || (type==RotationSettingType.Boolean && (min!=0 || max!=1 || step!=1)))
                    throw new FormatException("Setting bounds");
                var tier=Required(el,"tier");
                if(tier is not ("Essentials" or "Advanced"))throw new FormatException("Tier");
                string? exclusive=(string?)el.Attribute("exclusiveGroup");
                string? parent=(string?)el.Attribute("parent");
                int icon=el.Attribute("iconSpellId") is null?0:Number(el,"iconSpellId");
                if(icon<0 || icon>16777215 ||
                    (exclusive is not null &&
                        (type!=RotationSettingType.Boolean ||
                         !System.Text.RegularExpressions.Regex.IsMatch(exclusive,@"^[a-z][A-Za-z0-9]{0,63}$"))) ||
                    (parent is not null &&
                        !System.Text.RegularExpressions.Regex.IsMatch(parent,@"^[a-z][A-Za-z0-9]{0,63}$")))
                    throw new FormatException("Setting display/exclusive metadata");
                var s=new RotationSetting(id,type,Required(el,"unit"),def,min,max,step,tier,
                    Required(el,"group"),Required(el,"ru"),Required(el,"en"),
                    (string?)el.Attribute("descriptionRu")??"",
                    (string?)el.Attribute("descriptionEn")??"",icon,exclusive,parent);
                if(!settings.TryAdd(id,s) || settings.Count>128)throw new FormatException("Duplicate/too many settings");
            }
            foreach(var setting in settings.Values)
                if(setting.Parent is not null &&
                   (!settings.TryGetValue(setting.Parent,out var parentSetting) ||
                    parentSetting.Type!=RotationSettingType.Boolean ||
                    setting.Parent==setting.Id ||
                    parentSetting.Tier!=setting.Tier))
                    throw new FormatException("Invalid setting parent");
            foreach(var group in settings.Values.Where(x=>x.ExclusiveGroup is not null)
                .GroupBy(x=>x.ExclusiveGroup,StringComparer.Ordinal))
                if(group.Count(x=>x.Default==1)>1)
                    throw new FormatException("Conflicting exclusive defaults");
            var rules=new List<RotationRuleV2>();
            var ids=new HashSet<string>(StringComparer.Ordinal);
            var priorities=new HashSet<int>();
            var used=new HashSet<string>(StringComparer.Ordinal);
            foreach(var el in children[1].Elements())
            {
                if(el.Name!="Rule")throw new FormatException("Rule element");
                Attributes(el,"id","priority","spellId","enabledBy");
                var id=Required(el,"id");
                int priority=Number(el,"priority"),spell=Number(el,"spellId");
                if(!ids.Add(id) || priority<1 || priority>9999 || !priorities.Add(priority) ||
                   spell<1 || spell>16777215)throw new FormatException("Rule identity");
                string? enabled=(string?)el.Attribute("enabledBy");
                if(enabled!=null) {
                    if(!settings.TryGetValue(enabled,out var setting) || setting.Type!=RotationSettingType.Boolean)
                        throw new FormatException("enabledBy must reference bool");
                    used.Add(enabled);
                }
                var conditions=new List<RotationCondition>();
                foreach(var c in el.Elements())
                {
                    if(c.Name!="Condition" || c.HasElements)throw new FormatException("Condition");
                    Attributes(c,"signal","compare","settingRef","value","whenEnabled","spellId","spellIds");
                    string signal=Required(c,"signal");
                    if(signal=="TargetDebuffAbsent")
                    {
                        if((string?)c.Attribute("compare")!="IsTrue" ||
                            c.Attribute("settingRef") is not null ||
                            c.Attribute("value") is not null ||
                            c.Attribute("whenEnabled") is not null)
                            throw new FormatException("TargetDebuffAbsent syntax");
                        var single=(string?)c.Attribute("spellId");
                        var family=(string?)c.Attribute("spellIds");
                        if((single is null)==(family is null))
                            throw new FormatException("Exactly one aura spellId/spellIds");
                        int[] auraIds;
                        if(single is not null)
                        {
                            int auraId=Number(c,"spellId");
                            auraIds=new[]{auraId};
                        }
                        else
                        {
                            var parts=family!.Split(',');
                            if(parts.Length is <2 or >20 ||
                               parts.Any(x=>x.Length==0 || x.Trim()!=x ||
                                   !int.TryParse(x,NumberStyles.None,CultureInfo.InvariantCulture,out var parsedAuraId) ||
                                   parsedAuraId is <1 or >16777215))
                                throw new FormatException("Aura rank family");
                            auraIds=parts.Select(x=>int.Parse(x,CultureInfo.InvariantCulture)).ToArray();
                            if(auraIds.Distinct().Count()!=auraIds.Length)
                                throw new FormatException("Duplicate aura rank");
                        }
                        if(auraIds.Any(x=>x is <1 or >16777215))
                            throw new FormatException("Aura SpellID");
                        conditions.Add(new(signal,"IsTrue",null,null,null,auraIds[0],auraIds));
                        continue;
                    }
                    if(c.Attribute("spellId") is not null || c.Attribute("spellIds") is not null)
                        throw new FormatException("Only aura signal accepts spellId/spellIds");
                    string compare=Required(c,"compare");
                    if(signal is not ("PlayerHealthPercent" or "TargetHealthPercent" or "PowerPercent"))
                        throw new FormatException("Unsupported signal");
                    if(compare is not ("Below" or "AtLeast"))throw new FormatException("Unsupported compare");
                    string? key=(string?)c.Attribute("settingRef");
                    string? constant=(string?)c.Attribute("value");
                    if((key is null)==(constant is null))throw new FormatException("Exactly one comparison value");
                    int? number=null;
                    if(key!=null) {
                        if(!settings.TryGetValue(key,out var setting) || setting.Type!=RotationSettingType.Integer ||
                           setting.Unit!="percent" || (signal=="PowerPercent" && setting.Step!=5))
                            throw new FormatException("Incompatible parameter or non-5% power slider");
                        used.Add(key);
                    } else {
                        if(!int.TryParse(constant,NumberStyles.None,CultureInfo.InvariantCulture,out int v) ||
                            v<0 || v>100 || (signal=="PowerPercent" && v%5!=0))
                            throw new FormatException("Condition value");
                        number=v;
                    }
                    var gate=(string?)c.Attribute("whenEnabled");
                    if(gate is not null)
                    {
                        if(!settings.TryGetValue(gate,out var gateSetting) ||
                           gateSetting.Type!=RotationSettingType.Boolean)
                            throw new FormatException("whenEnabled must reference bool");
                        used.Add(gate);
                    }
                    conditions.Add(new(signal,compare,key,number,gate));
                    if(conditions.Count>16)throw new FormatException("Too many conditions");
                }
                rules.Add(new(id,priority,spell,enabled,conditions));
                if(rules.Count>100)throw new FormatException("Too many rules");
            }
            if(rules.Count==0 || settings.Keys.Any(k=>!used.Contains(k)))
                throw new FormatException("Empty rules or unused UI setting");
            return new(client,classId,specIndex,mode,settings,rules.OrderBy(r=>r.Priority).ToArray());
        }
        catch(XmlException ex) { throw new FormatException("Invalid/unsafe XML",ex); }
    }

    public static IReadOnlyDictionary<string,int> Resolve(RotationProfileV2 profile,
        IReadOnlyDictionary<string,int>? overrides)
    {
        var values=profile.Settings.ToDictionary(x=>x.Key,x=>x.Value.Default,StringComparer.Ordinal);
        if(overrides is null)return values;
        foreach(var (key,value) in overrides)
        {
            if(!profile.Settings.TryGetValue(key,out var s) || value<s.Min || value>s.Max ||
                (value-s.Min)%s.Step!=0)throw new FormatException("Invalid override: "+key);
            values[key]=value;
        }
        foreach(var group in profile.Settings.Values.Where(x=>x.ExclusiveGroup is not null)
            .GroupBy(x=>x.ExclusiveGroup,StringComparer.Ordinal))
            if(group.Count(x=>values[x.Id]==1)>1)
                throw new FormatException("Conflicting exclusive toggles: "+group.Key);
        return values;
    }
    // Diagnostics only. Separate CanExecute policy must be implemented and verified before any keys.
    public static RotationEvaluation Evaluate(RotationProfileV2 profile, GameState state,
        IReadOnlyDictionary<string,int>? overrides,DateTimeOffset now,string mode)
    {
        var traces=new List<RotationRuleTrace>();
        if(now<state.CapturedAt || now-state.CapturedAt>TimeSpan.FromMilliseconds(900))
            return new(null,traces,"Snapshot expired");
        var fresh=state.Age(now,TimeSpan.FromMilliseconds(900));
        if(state.Client!=profile.Client || mode!=profile.Mode ||
            fresh.ClassId.Is(x=>x==profile.ClassId)!=Truth.True ||
            fresh.SpecIndex.Is(x=>x==profile.SpecIndex)!=Truth.True)
            return new(null,traces,"Profile identity or mode unknown/mismatch");
        // Always produce an explanatory trace for safe diagnostics, even if the
        // global gate is Unknown. The resulting Recommendation remains blocked.
        var targetGate=ConditionEvaluator.AttackTarget(fresh);
        var gcdGate=ConditionEvaluator.GcdReady(fresh);
        var globalGate=TruthLogic.And(targetGate,gcdGate);
        var values=Resolve(profile,overrides);
        foreach(var rule in profile.Rules)
        {
            var details=new List<string>();
            Truth result=rule.EnabledBy is null?Truth.True:
                values[rule.EnabledBy]==1?Truth.True:Truth.False;
            if(rule.EnabledBy is not null)
                details.Add(rule.EnabledBy+"="+values[rule.EnabledBy]);
            foreach(var c in rule.Conditions)
            {
                if(c.WhenEnabled is not null && values[c.WhenEnabled]==0)
                {
                    details.Add(c.WhenEnabled+"=0 (conditional limit skipped)");
                    continue;
                }
                if(c.Signal=="TargetDebuffAbsent")
                {
                    var epoch=fresh.TargetEpoch;
                    var ids=c.AuraRanks??new[]{c.AuraSpellId!.Value};
                    Truth absent=Truth.Unknown;
                    if(epoch.Quality==Knowledge.Known && epoch.Value is >=0)
                    {
                        var rankResults=new List<Truth>();
                        foreach(int auraId in ids)
                        {
                            var key=new AuraKey("target-epoch-"+epoch.Value,auraId,true);
                            rankResults.Add(fresh.Auras.TryGetValue(key,out var aura)
                                ? TruthLogic.Not(aura.Present.Is(v=>v))
                                : Truth.Unknown);
                        }
                        absent=TruthLogic.And(rankResults.ToArray());
                        // Sonah-style successful-cast estimate: only use when
                        // direct aura status is Unknown. A complete observed
                        // absent/present list wins over inferred effects.
                        // This is advisory for selecting the next XML rule,
                        // never proof of a debuff hit or an HID authorization.
                        if(absent==Truth.Unknown && ids.Length>0 &&
                           fresh.TargetDebuffCastHints.TryGetValue(ids[0],out var hint) &&
                           hint.Is(x=>x)==Truth.True)
                        {
                            absent=Truth.False;
                            details.Add("CAST_ESTIMATE (SPELLCAST_SUCCEEDED, not observed aura)");
                        }
                    }
                    result=TruthLogic.And(result,absent);
                    details.Add("TargetDebuffAbsent ranks="+string.Join(",",ids)+
                        " epoch="+epoch.Quality+" result="+absent);
                    continue;
                }
                int threshold=c.SettingRef is null?c.Constant!.Value:values[c.SettingRef];
                Truth answer;
                Knowledge quality;
                if(c.Signal=="PowerPercent")
                {
                    // Forever Curve reports bands (e.g. 20..24), never precise power.
                    // Entire observed interval must satisfy the threshold.
                    var band=fresh.PowerBand;
                    quality=band.Quality;
                    answer=band.Is(v=>v.IsFivePercentCurveBand &&
                        (c.Compare=="Below"?v.Upper<threshold:v.Lower>=threshold));
                    if(band.Quality==Knowledge.Known &&
                       band.Value is HealthBand invalid && !invalid.IsFivePercentCurveBand)
                        answer=Truth.Unknown;
                    details.Add("CurveBand="+(band.Value?.ToString()??"Unknown"));
                }
                else
                {
                    var observed=c.Signal=="PlayerHealthPercent"?
                        fresh.PlayerHealthPercent:fresh.TargetHealthPercent;
                    quality=observed.Quality;
                    answer=observed.Is(v=>c.Compare=="Below"?v<threshold:v>=threshold);
                }
                result=TruthLogic.And(result,answer);
                details.Add(c.Signal+" "+c.Compare+" "+(c.SettingRef??"literal")+
                    "="+threshold+" ("+quality+" => "+answer+")");
            }
            result=TruthLogic.And(result,globalGate);
            details.Add("TargetGate="+targetGate+"; GcdGate="+gcdGate);
            // Hunter XML references family/base IDs. Live compact RGB observes
            // individual ranks: use ONLY a completely verified learned family,
            // never assume the base rank is known or highest by player level.
            int chosenSpellId=rule.SpellId;
            Truth readiness;
            if(profile.Client=="forever" && profile.ClassId==3)
            {
                var finding=HunterSpellFamilies.Find(fresh,rule.SpellId,now);
                if(finding.SelectedRank is int verifiedRank)
                {
                    chosenSpellId=verifiedRank;
                    readiness=ConditionEvaluator.SpellReady(fresh,verifiedRank);
                }
                else readiness=Truth.Unknown;
                details.Add("HunterRank="+finding.Status+
                    (finding.SelectedRank is int rankId?" selected="+rankId:""));
            }
            else readiness=ConditionEvaluator.SpellReady(fresh,rule.SpellId);
            result=TruthLogic.And(result,readiness);
            details.Add("SpellReady="+readiness);
            traces.Add(new(rule.Id,chosenSpellId,result,
                string.Join("; ",details)+"; outcome="+result+"; diagnostic only"));
            if(result==Truth.True)
                return new(new(RotationSourceId.Internal,chosenSpellId,rule.Priority,rule.Id,now),traces,"");
        }
        return new(null,traces,globalGate!=Truth.True?
            "Target, transport or GCD unknown/blocked":"No eligible rules");
    }
}
