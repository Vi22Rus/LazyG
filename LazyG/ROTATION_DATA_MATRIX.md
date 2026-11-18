# LazyG — матрица условий Sonah/RoseSlayer для WoW Forever

> **Аналитический документ; не сертификат доступности WoW API.** Источники: `Sonah.zip/Sonah/Core/Molecules/Conditions.lua`, `Sonah.zip/Sonah/Core/Atoms/*.lua`, `Sonah.zip/Sonah/Classes/*.lua`; `RoseSlayer_dev.zip/Molecules/Conditions.lua` и его классы. Код ротаций не перенесён и не скопирован. Дата: 2026-11-18.

## 1. Принцип состояния

- `Known` — значение действительно получено и подтверждено текущим декодером. `Unknown` — сигнала нет; `Protected` — клиент отклонил доступ; `Stale` — данные устарели.
- Bool-телеметрия: `True/False/Unknown`. `Unknown` **не равен** `False`; отдельная политика для каждого условия, неизвестные входные параметры по умолчанию **запрещают рекомендацию**.
- Для аур ключ = (unit GUID, SpellID, тип buff/debuff); для спелла = (client, class, SpellID). Начальный GameState является только каркасом; GUID и ауры ещё не передаются.
- **RGB v2**: класс, раса, уровень, дерево талантов при его определении, наличие/враждебность/живость цели, состояние боя. **CRC v3** подтверждает целостность пакета, но не достоверность защищённого HP/GCD.
- Отдельные Curve-пробы позволили видеть диапазон HP цели; не переносить их в готовые игровые решения без динамических проверок всех порогов.

## 2. Полная систематизация молекул C.*

| Подсистема | Названия условий из `Conditions.lua` | Зависимости Atoms | Доступность в текущем LazyG | Приоритет |
|---|---|---|---|---|
| Комбинаторы и логика | `C.all`, `C.any`, `C.no`, `C.fn`, `C.atLeast`, `C.always`, `C.never` | движок правил | Windows / без телеметрии | P0 |
| Способности, доступность, кулдауны, проки, история | `C.known`, `C.unknown`, `C.ready`, `C.usable`, `C.usableStrict`, `C.cooldownOver`, `C.cooldownUnder`, `C.noPower`, `C.wentOOM`, `C.hasPower`, `C.autoActive`, `C.proc`, `C.notRecent`, `C.consumed`, `C.castPending`, `C.inRange`, `C.inRangeKnown`, `C.outOfRange`, `C.charges`, `C.current`, `C.lastCastAmong`, `C.castWithinDuration` | Spells, Casts, ActionSlots | изученность/usable/cooldown/gcd/proc/range не передаются; требуется новый RGB поток | P1 |
| Ауры, DoT, бафы группы, чары оружия | `C.buff`, `C.buffMissing`, `C.buffStacks`, `C.debuff`, `C.debuffMissing`, `C.dotRefresh`, `C.stacksBelow`, `C.stacksAtLeast`, `C.debuffStacksBelow`, `C.weaponEnchantMissing`, `C.groupBuffUp`, `C.groupBuffMissing`, `C.noGroupBuff` | Auras, Spells, Units, Secret | ауры отсутствуют; нужен GUID, длительность, стаки, источник, история | P1 |
| Ресурсы и Combo Points | `C.rage`, `C.rageBelow`, `C.energy`, `C.energyBelow`, `C.focus`, `C.combo`, `C.comboBelow`, `C.manaPct`, `C.manaBelow`, `C.manaKnownAbove`, `C.spareMana`, `C.spareRage` | Units, Spells, Secret | процент через Curve экспериментально; точная сила ресурса скрыта | P1 |
| HP, HP цели, питомца | `C.targetBelow`, `C.targetAbove`, `C.targetKnownAbove`, `C.healthBelow`, `C.healthAbove`, `C.petHappinessBelow`, `C.petHealthBelow` | Units, Curves, Secret | target HP по Curve 10% подтверждался; 5% эксперимент | P1 |
| Лечение группы, диспел, лок-ауты | `C.healBelow`, `C.healHidden`, `C.healFallback`, `C.healingOther`, `C.groupBelow`, `C.partyBelow`, `C.healMissing`, `C.healDispellable`, `C.healDispellableAny`, `C.selfDispellableAny`, `C.selfDispellable`, `C.groupHealthHidden`, `C.healLockoutFree` | Units, Auras, Items | группа/диспел/выбор союзника ещё не транспортируются | P2 |
| Бой, движение, PvP, таланты, предметы, агро, окружение | `C.inCombat`, `C.targetCasting`, `C.targetInterruptible`, `C.outOfCombat`, `C.hasPet`, `C.noPet`, `C.petDead`, `C.inGroup`, `C.solo`, `C.inRaid`, `C.questing`, `C.groupContent`, `C.dungeonContent`, `C.raidContent`, `C.efficient`, `C.balanced`, `C.maxDamage`, `C.style`, `C.allowed`, `C.assignedTank`, `C.targetElite`, `C.targetBoss`, `C.targetSkull`, `C.targetIsPlayer`, `C.inPvP`, `C.notPvP`, `C.selfReliant`, `C.targetClass`, `C.targetClassOrUnknown`, `C.targetNear`, `C.autoSwapping`, `C.lossOfControl`, `C.lossOfControlFrom`, `C.targetPurgeable`, `C.partyBuffMissing`, `C.hasItem`, `C.rangedWeapon`, `C.hasAmmo`, `C.pvpTrinket`, `C.damageTrinket`, `C.eating`, `C.notCasting`, `C.moving`, `C.standing`, `C.hasTarget`, `C.itemGroupReady`, `C.swingEarly`, `C.swingSinceCast`, `C.weaponSpeedAtLeast`, `C.level`, `C.levelBelow`, `C.form`, `C.noForm`, `C.talent`, `C.noTalent`, `C.enemies`, `C.creature`, `C.creatureOrUnknown`, `C.spec`, `C.setting`, `C.aggro`, `C.noAggro` | Units, Casts, Character, Talents, Items, ActionSlots | только отдельные combat flags + class/spec/level по v2; остальные неизвестны | P1/P2 |

## 3. Классы и требуемые C.* условия

> Списки ниже автоматически извлечены из вызовов вида `C.name(` в оригинальных Lua-файлах классов. Они не включают прямые обращения к `Atoms` или пользовательские замыкания `C.fn` — они требуют отдельного разбора.

| Класс | Различных C.* вызовов | Условия |
|---|---:|---|
| Warrior | 34 | `all`, `any`, `autoActive`, `buffMissing`, `creature`, `current`, `debuffMissing`, `dotRefresh`, `enemies`, `fn`, `form`, `healthAbove`, `healthBelow`, `inRange`, `known`, `levelBelow`, `lossOfControl`, `lossOfControlFrom`, `no`, `noPower`, `noTalent`, `notRecent`, `outOfRange`, `rage`, `ready`, `spareRage`, `stacksBelow`, `talent`, `targetAbove`, `targetBelow`, `targetClass`, `targetClassOrUnknown`, `unknown`, `usable` |
| Paladin | 41 | `all`, `any`, `buff`, `buffMissing`, `castPending`, `consumed`, `cooldownOver`, `creature`, `creatureOrUnknown`, `debuff`, `debuffMissing`, `fn`, `groupBelow`, `groupBuffMissing`, `groupBuffUp`, `hasPower`, `healBelow`, `healDispellable`, `healDispellableAny`, `healMissing`, `healthBelow`, `inRange`, `known`, `level`, `levelBelow`, `lossOfControl`, `manaPct`, `no`, `noGroupBuff`, `notRecent`, `proc`, `questing`, `ready`, `selfDispellable`, `selfDispellableAny`, `spec`, `stacksBelow`, `talent`, `unknown`, `usable`, `weaponSpeedAtLeast` |
| Hunter | 33 | `all`, `any`, `autoActive`, `autoSwapping`, `buff`, `buffMissing`, `consumed`, `debuffMissing`, `dotRefresh`, `enemies`, `hasPower`, `healthBelow`, `inRange`, `inRangeKnown`, `known`, `level`, `levelBelow`, `no`, `notRecent`, `petHappinessBelow`, `petHealthBelow`, `proc`, `rangedWeapon`, `setting`, `spareMana`, `spec`, `stacksBelow`, `style`, `talent`, `targetAbove`, `targetClass`, `unknown`, `usable` |
| Rogue | 33 | `all`, `any`, `buff`, `buffMissing`, `combo`, `comboBelow`, `cooldownOver`, `cooldownUnder`, `debuff`, `debuffMissing`, `enemies`, `energyBelow`, `fn`, `form`, `healthBelow`, `known`, `level`, `levelBelow`, `lossOfControl`, `no`, `noPower`, `noTalent`, `notRecent`, `proc`, `selfReliant`, `talent`, `targetAbove`, `targetBelow`, `targetIsPlayer`, `unknown`, `usable`, `usableStrict`, `weaponEnchantMissing` |
| Priest | 34 | `all`, `any`, `buffMissing`, `castPending`, `creature`, `debuffMissing`, `dotRefresh`, `enemies`, `groupBelow`, `healBelow`, `healDispellable`, `healLockoutFree`, `healMissing`, `healthAbove`, `healthBelow`, `known`, `level`, `levelBelow`, `manaBelow`, `manaPct`, `no`, `noPower`, `notRecent`, `partyBelow`, `partyBuffMissing`, `rangedWeapon`, `ready`, `spareMana`, `talent`, `targetAbove`, `targetBelow`, `targetClassOrUnknown`, `unknown`, `usable` |
| Shaman | 41 | `all`, `any`, `buff`, `buffMissing`, `buffStacks`, `castPending`, `castWithinDuration`, `debuffMissing`, `dotRefresh`, `enemies`, `form`, `groupBelow`, `hasPower`, `healBelow`, `healDispellable`, `healMissing`, `healthBelow`, `inRange`, `inRangeKnown`, `known`, `lastCastAmong`, `level`, `levelBelow`, `manaBelow`, `manaPct`, `no`, `noPower`, `noTalent`, `notRecent`, `outOfRange`, `proc`, `ready`, `solo`, `stacksAtLeast`, `talent`, `targetAbove`, `targetBelow`, `targetClass`, `unknown`, `usable`, `weaponEnchantMissing` |
| Mage | 41 | `all`, `any`, `buff`, `buffMissing`, `buffStacks`, `castPending`, `cooldownOver`, `debuff`, `enemies`, `fn`, `hasItem`, `hasPower`, `healthBelow`, `inRange`, `itemGroupReady`, `known`, `level`, `levelBelow`, `lossOfControl`, `manaBelow`, `manaPct`, `no`, `noPower`, `notRecent`, `partyBuffMissing`, `proc`, `rangedWeapon`, `ready`, `selfDispellable`, `spareMana`, `spec`, `stacksAtLeast`, `stacksBelow`, `style`, `talent`, `targetAbove`, `targetBelow`, `targetClassOrUnknown`, `unknown`, `usable`, `wentOOM` |
| Warlock | 37 | `all`, `allowed`, `any`, `buff`, `buffMissing`, `consumed`, `debuffMissing`, `dotRefresh`, `enemies`, `fn`, `hasItem`, `healthAbove`, `healthBelow`, `itemGroupReady`, `known`, `lastCastAmong`, `level`, `levelBelow`, `manaBelow`, `manaPct`, `no`, `noPower`, `noTalent`, `notRecent`, `petHealthBelow`, `proc`, `rangedWeapon`, `spec`, `stacksAtLeast`, `stacksBelow`, `style`, `talent`, `targetAbove`, `targetBelow`, `unknown`, `usable`, `weaponEnchantMissing` |
| Druid | 46 | `all`, `any`, `autoActive`, `buff`, `buffMissing`, `buffStacks`, `castPending`, `combo`, `cooldownOver`, `cooldownUnder`, `debuffMissing`, `dotRefresh`, `enemies`, `energyBelow`, `form`, `groupBelow`, `healBelow`, `healDispellable`, `healMissing`, `healthAbove`, `healthBelow`, `known`, `lastCastAmong`, `level`, `levelBelow`, `lossOfControl`, `manaBelow`, `manaPct`, `no`, `noPower`, `noTalent`, `notRecent`, `outOfRange`, `proc`, `rage`, `rageBelow`, `stacksAtLeast`, `stacksBelow`, `style`, `talent`, `targetAbove`, `targetClassOrUnknown`, `targetInterruptible`, `targetKnownAbove`, `unknown`, `wentOOM` |

## 4. Данные для RGB: практическая детальная матрица

| Поле / группа | Кто производит | Условия-потребители | Формат передачи | Статус на 0.2.5-dev | Стадия |
|---|---|---|---|---|---|
| Класс/раса/уровень/дерево | UnitClass / UnitRace / UnitLevel / Talents | known, spec, level, levelBelow | байты + Unknown для дерева 0 | RGB v2 подтверждён частично | 1 |
| Цель: есть/враг/жива/в бою | UnitExists / UnitCanAttack / UnitIsDeadOrGhost / UnitAffectingCombat | hasTarget, targetIsPlayer, inCombat | битовые флаги, version, CRC | RGB v2 есть базовые флаги | 1 |
| GUID игрока, цели, питомца | Units.GUID | debuff, dotRefresh, targetClass | стабильный хэш/epoch, срок жизни | отсутствует | 1 |
| Заклинания изучены, ранг | Spells.Known / Spells.Resolve / Talents | known, unknown, talent | актуальные SpellID/ранги по событиям | отсутствует | 1 |
| Spell usable + noMana | Spells.Usable | usable, usableStrict, noPower, hasPower, wentOOM | 3 значения + причина / SpellID | отсутствует | 1 |
| Spell cooldown remaining/charges | Spells.CooldownRemaining / Spells.Charges | ready, cooldownUnder, cooldownOver, charges | по SpellID, время, источник, epoch | отсутствует | 1 |
| GCD и длительность | Spells.GCDRemaining / Spells.GCDEstimate | ready / engine preflight | измерение/оценка, таймстамп | только 1500 мс DEMO в UI | 1 |
| Каст игрока, канал, событие успеха | Casts / Spells.NoteCast | current, notRecent, consumed, castPending | SpellID + start/end + GUID цели | отсутствует | 1 |
| Каст цели и interruptible | Casts.TargetCasting / TargetInterruptible | targetCasting, targetInterruptible | bool? + remaining + spellID | отсутствует | 1 |
| Бафф/дебафф и длительность | Auras.Buff/Debuff + Secret | buff, debuff, buffMissing, dotRefresh | (GUID, SpellID, type) + state, source, ms | отсутствует | 1 |
| Стаки и зачарование оружия | Auras.Stacks / WeaponEnchants | buffStacks, stacksBelow, weaponEnchantMissing | аура+число или Unknown, hand | отсутствует | 1 |
| HP игрока и цели | Units / Curves / Secret | healthBelow, targetBelow, targetAbove | percent bucket с quality или Unknown | Curve target HP 10% подтверждено; 5% эксперимент | 1 |
| Power type/value/max/percent | Units.Power / Secret / Curves | rage, energy, focus, manaPct, spareMana | type + exact/bucket + quality | protected для прямых чисел | 1 |
| Combo Points, формы, стойки | Units / Talents | combo, comboBelow, form, noForm | очки+тип формы+source | отсутствует | 2 |
| Дистанция/LOS, AutoAttack | Spells.InRange / Units / ActionSlots | inRange, outOfRange, autoActive | для каждого spell in/out/unknown; автоатака | отсутствует | 1 |
| Движение и оружие | Units / Casts / Items | moving, standing, rangedWeapon, swingEarly | флаги, скорость оружия, тайминги | отсутствует | 2 |
| Питомец, HP, счастье, смерть | Units / Auras | hasPet, petDead, petHealthBelow, petHappinessBelow | unit guid + health buckets + statuses | только v3 petHealth status эксперимент | 2 |
| Кол-во врагов/босс/существо | Units.EnemiesNearby / Classification | enemies, targetElite, targetBoss, creature | bucket enemies, classification, ttl | отсутствует | 2 |
| Таланты/спеки/экипировка | Talents / Character / Items | talent, noTalent, weaponSpeedAtLeast | канонический talent ID+rank+item slots | спек v2 грубо | 2 |
| Группа/рейд/выбор союзника | Units / Auras / HealTarget | healBelow, groupBelow, healMissing | unitID/GUID, eligible, HP, role | отсутствует | 3 |
| Очищение/диспел/дебафы союзников | Auras.HasDispellable / HealTarget | healDispellable, selfDispellable | тип дебафа+идентификатор цели | отсутствует | 3 |
| Предметы/расходники/тринкеты | Items / ActionSlots | hasItem, itemGroupReady, damageTrinket | itemID+usable+cooldown/group | отсутствует | 3 |
| PvP/control/agro/content | Units / Character / EventState | inPvP, lossOfControl, aggro, questing | битовые флаги и source | отсутствует | 2 |
| Пользовательские опции | Settings / rotation profile | style, setting, allowed, spec | локальный UI / XML; НЕ нужен RGB | можно реализовать независимо | 2 |
| Shared CDs и послекастовые оценки | Spells.RegisterSharedCd / Auras tracking | cooldownOver, notRecent, dotRefresh | Windows derived ledger + validation | нет стабильной истории | 2 |

## 5. Поэтапный план подключения

1. **0.2.6-dev (первый кодовый шаг):** чистый C# GameState, типизированные Known/Unknown/Protected/Stale и Truth, базовые проверки, адаптер имеющихся RGB v2-флагов, экран диагностик, тесты. **Никаких ротаций и новых Lua API.**
2. **RGB следующей версии:** отдельный versioned extension/manifest, фиксированная схема, CRC, sequence, TTL; вначале learned/usable/cooldown/GCD/cast, не менять старые RGB v2/v3.
3. **Aura+GUID:** проверки эффекта на конкретной цели, источник, стеки, окончания, история каста; учитывать смену цели и невозможность точного чтения.
4. **HP/resource/Curve:** отдельные динамические проверки protected API/5% Curve в игре; запрещать принятие решения по неподтверждённому диапазону.
5. **Rotation XML read-only:** сначала Hunter Beast Mastery, запись причины выбора SpellID в диагностике и Overlay, без нажатий и без неверной метки готовности.
6. **Комплексные классы:** питомец, combo, формы, shared CDs, AoE, диспел, healing, items и PvP; каждый клиент и протокол изолированы.

## 6. Нюансы достоверности

- Проверка `C.ready` в Sonah может трактовать неизвестный cooldown как готовый; **LazyG по умолчанию не должен повторять этот оптимизм**, пока не будет собственного источника уверенности.
- Соняховские `C.buffMissing`, `C.debuffMissing` имеют историю кастов как fallback: не эквивалентны прямому `HasAura=false`.
- `C.fn` и вложенные определения класса требуют индивидуального преобразования; одной табличной конвертации в XML недостаточно.
- Реальный GCD не получен: в 0.2.5-dev циклическая визуальная DEMO анимация на 1.5 секунды.
- Не считать успешную сборку GitHub Actions игровым тестированием.