using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Xml;
using System.Xml.Linq;

namespace LazyG.Desktop.Engine;

// Self-contained, diagnostics-only XML rotation planner for Forever.
// It returns a suggestion record, never keys, inputs, or game actions.
// The global hostile-target gate lives INSIDE this dispatch boundary.
internal enum XmlActionKind { Attack, Execute }

internal sealed record XmlRotationRule(int Priority, int SpellId,
    XmlActionKind Kind, int? TargetHpBelow);
internal sealed record XmlRotationProfile(string Client, IReadOnlyList<XmlRotationRule> Rules);
internal sealed record XmlRotationSuggestion(int SpellId, XmlActionKind Kind, int Priority);

internal static class XmlRotationDispatcher
{
    private const int MaxXmlChars=65536;
    private static readonly TimeSpan MaxSnapshotAge=TimeSpan.FromMilliseconds(900);

    public static XmlRotationProfile Parse(string xml)
    {
        if(string.IsNullOrWhiteSpace(xml) || xml.Length>MaxXmlChars)
            throw new FormatException("Missing or oversized rotation XML.");
        try
        {
            using var reader=XmlReader.Create(new StringReader(xml),new XmlReaderSettings
            {
                DtdProcessing=DtdProcessing.Prohibit,
                XmlResolver=null,
                MaxCharactersInDocument=MaxXmlChars,
                IgnoreComments=true,
                IgnoreWhitespace=true
            });
            var document=XDocument.Load(reader,LoadOptions.None);
            var root=document.Root;
            if(root is null || root.Name!="Rotation" ||
               root.Attributes().Any(a=>a.Name!="client" && a.Name!="version") ||
               (string?)root.Attribute("client")!="forever" ||
               (string?)root.Attribute("version")!="1" ||
               root.Nodes().Any(n=>n is not XElement))
                throw new FormatException("Unsupported rotation root.");
            var rules=new List<XmlRotationRule>();
            var priorities=new HashSet<int>();
            foreach(var element in root.Elements())
            {
                if(element.Name!="Rule" || element.HasElements || !string.IsNullOrWhiteSpace(element.Value) ||
                   element.Attributes().Any(a=>a.Name!="priority" &&
                       a.Name!="spellId" && a.Name!="kind" && a.Name!="targetHpBelow"))
                    throw new FormatException("Unsupported rotation rule.");
                if(!int.TryParse((string?)element.Attribute("priority"),out var priority) ||
                   priority<1 || priority>9999 || !priorities.Add(priority) ||
                   !int.TryParse((string?)element.Attribute("spellId"),out var spell) ||
                   spell<1 || spell>16777215)
                    throw new FormatException("Invalid priority or SpellID.");
                var kind=(string?)element.Attribute("kind") switch
                {
                    "Attack"=>XmlActionKind.Attack,
                    "Execute"=>XmlActionKind.Execute,
                    _=>throw new FormatException("Unsupported action kind.")
                };
                int? threshold=null;
                if(kind==XmlActionKind.Execute)
                {
                    if(!int.TryParse((string?)element.Attribute("targetHpBelow"),out var value) ||
                       value<1 || value>100)
                        throw new FormatException("Execute requires targetHpBelow 1..100.");
                    threshold=value;
                }
                else if(element.Attribute("targetHpBelow") is not null)
                    throw new FormatException("HP threshold requires Execute kind.");
                rules.Add(new XmlRotationRule(priority,spell,kind,threshold));
                if(rules.Count>100)
                    throw new FormatException("Too many rotation rules.");
            }
            if(rules.Count==0)throw new FormatException("Empty rotation.");
            return new XmlRotationProfile("forever",rules.OrderBy(x=>x.Priority).ToArray());
        }
        catch(XmlException e){throw new FormatException("Invalid or unsafe rotation XML.",e);}
    }

    // Only fresh, fully-known observations can authorize *a suggestion*.
    // The planner never simulates a ready cooldown or guesses a GCD.
    // It intentionally has NO fallback to unguarded or untyped actions.
    public static XmlRotationSuggestion? Evaluate(XmlRotationProfile? profile,
        GameState? state, Observed<HealthBand> targetBand, DateTimeOffset now)
    {
        if(profile is null || state is null || profile.Client!="forever" ||
           state.Client!="forever" || state.CapturedAt>now ||
           now-state.CapturedAt>MaxSnapshotAge)
            return null;
        var fresh=state.Age(now,MaxSnapshotAge);
        if(ConditionEvaluator.AttackTarget(fresh)!=Truth.True ||
           ConditionEvaluator.GcdReady(fresh)!=Truth.True)
            return null;

        var band=targetBand.At(now,MaxSnapshotAge);
        foreach(var rule in profile.Rules)
        {
            // Never trust a forged caller-supplied rule or unknown enum.
            if(rule.SpellId<=0 || rule.SpellId>16777215)continue;
            bool allowed=rule.Kind switch
            {
                XmlActionKind.Attack=>
                    ConditionEvaluator.CanRecommendTargetedAttack(fresh,rule.SpellId),
                XmlActionKind.Execute when rule.TargetHpBelow is >=1 and <=100=>
                    ConditionEvaluator.CanRecommendExecute(fresh,rule.SpellId,band,
                        rule.TargetHpBelow.Value),
                _=>false
            };
            if(allowed)return new XmlRotationSuggestion(rule.SpellId,rule.Kind,rule.Priority);
        }
        return null;
    }
}
