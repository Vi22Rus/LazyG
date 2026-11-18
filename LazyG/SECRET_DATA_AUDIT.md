# LazyG — углублённый аудит защищённых игровых данных
**Источники:** `JustAC.zip` (175 ZIP-записей; 125 Lua-файлов с библиотеками), `Sonah.zip` (102 ZIP-записи; 83 Lua-файла). Дата анализа: 18.11.2026. Проверены сами исходные файлы, а не описания аддонов. Текущий код LazyG прочитан из `Vi22Rus/LazyG/main` (`PROJECT_CONTEXT.md`, `CHANGELOG.md`, `ROTATION_DATA_MATRIX.md`, `Engine/GameState.cs`, `RgbV3Thresholds.lua`).

**Статусы доказательств:** [КОД] — приём найден в Lua; [АВТОР] — комментарий автора сообщает о проверке в игре, но здесь она не повторена; [LAZYG] — есть пользовательские результаты LazyG; [ГИПОТЕЗА] — требует эксперимента в клиенте Forever. «Источник предлагает механизм» ≠ «он проверен для нашей версии клиента». `JustAC.toc`: `Interface: 120105, 16001`, версия `6.0.0.1`, GPL-3.0-or-later; код смешивает API 12.x и специальный профиль Forever. Не переносить реализацию GPL-кода в собственный EXE; перенимать требования и самостоятельно реализовывать алгоритмы.

## 1. Принципиальные ограничения

1. В WoW секретность распространяется на **значение, поле таблицы или объект**, а не просто на имя функции. `issecretvalue(x)` и `pcall` позволяют диагностировать недоступность, но не превращают запрещённое значение в обычное. [КОД: `JustAC/BlizzardAPI.lua:25–80`; `Sonah/Core/Atoms/Secret.lua:1–260`]
2. «Секретное» можно передать **в специально допускающий его UI-приёмник** (`StatusBar:SetValue`, `Region:SetAlphaFromBoolean`, `Cooldown:SetCooldownFromDurationObject`, `FontString:SetText`) **без получения исходного числа**. Наличие отображения ещё не является подтверждением, что Lua вправе сравнивать/читать результат. [КОД: `Sonah/Core/Atoms/Curves.lua:1–270`; `JustAC/BlizzardAPI/StateHelpers.lua:2106–2155`; `JustAC/UI/UIHealthBar.lua:329–355`]
3. Некоторые приёмы JustAC **сознательно экспериментальные/недокументированные** (например, бинарная проверка через `FontString:GetText` и проверка активности `Cooldown:IsShown`), и могут перестать работать после обновления клиента. Авторы прямо об этом предупреждают. [КОД: `JustAC/BlizzardAPI/SecretValues.lua:110–235`; `JustAC/BlizzardAPI/CooldownTracking.lua:140–170`]
4. Для решения о рекомендации каждому полю нужны `source`, `quality`, `timestamp`, `unit/target identity` и `availability`. `nil`, `false`, `0`, «нет цели», «секретно» и «устарело» — разные состояния. У JustAC разные слои специально делают `fail-open`, чтобы **не скрывать подсказки**; LazyG не должен трактовать это как безопасное основание для автоматического ввода.
5. Отдельное **живое состояние доступности**: `C_Secrets.ShouldCooldownsBeSecret`, `ShouldAurasBeSecret`, `HasSecretRestrictions`; последнее — флаг сборки/режима, а не обязательное доказательство, что каждое поле сейчас секретно. [КОД: `JustAC/BlizzardAPI.lua:57–87`; `Sonah/Core/Atoms/Secret.lua:238–260`]

## 2. Полная прикладная матрица механизмов

| № | Семейство/состояние | Что делает JustAC | Что делает Sonah | Для LazyG: что считать подтверждённым и что проверить |
|---:|---|---|---|---|
| 01 | Секретность отдельного значения | `IsSecretValue`, `Unsecret`, осторожные `pcall` | `Secret.Is`, `Call`, `Fields`, `CallNumber/CallBool` | Вводить качество по полям, запрещать использование `Unknown` как `false` |
| 02 | Контекст секретности | `C_Secrets.ShouldCooldownsBeSecret`, `ShouldAurasBeSecret`, `GetSpellAuraSecrecy` | `Secret.AurasHidden`, `RestrictionsActive` | Динамически определять семейства API; проверять наличие методов на Forever |
| 03 | Точный HP игрока | `GetPlayerHealthPercent` читает `UnitHealth/Max`, возвращает `nil` при секрете | `Units.HealthPercent` аналогично; без числа использует оценку событий | [LAZYG] точное HP ранее давало protected/API error. Не создавать фиктивный процент |
| 04 | Точный HP цели | Прямое чтение может быть недоступно | `Units.HealthPercent`, оценка урона/лечения и изученного максимума NPC | [ГИПОТЕЗА] калибровка по нормальным NPC, исключать элитных и боссов |
| 05 | HP ниже конкретного X% | `IsUnitHealthBelow` — `UnitHealthPercent(unit,false,curve)` и экспериментальная нулевая проверка | `Curves.HealthBelowAlpha` — curve значение напрямую задаёт `Region:SetAlpha` | [LAZYG] 10% Curve-разбиение HP цели пользователь подтвердил, шаг 5% не полностью проверен; новый бинарный путь тестировать отдельно |
| 06 | Диапазон HP | `GetHealthBand(unit,boundaries)` — короткая последовательность *значимых для решения* порогов | Пороговые/цветные Curve в UI, отдельная оценка HP | Не принимать диапазон за точный процент, хранить границы и степень доверия |
| 07 | HP полностью заполнено | `UnitHealthMissing` + `IsSecretZero` | Прямое чтение или оценка | Приём Zero-gate крайне хрупкий; не делать без защищённой самопроверки и тестов |
| 08 | «Низкое HP» через UI | `LowHealthFrame:IsShown`; автор отказывается оценивать процент по Alpha | Собственные Curve-виджеты | Только слабый признак: FULLSCREEN vignette может зависеть от CVar и боя |
| 09 | HP питомца | `GetPetHealthPercent` → nil при секрете; `GetPetStatus` (dead/missing/alive) | Учёт `UNIT_COMBAT` WOUND/HEAL и доступного UnitHealthMax | Разделить состояние питомца и его здоровье; не лечить отсутствующего питомца |
| 10 | HP группы | `GetPartyLowCount`, `IsUnitLow` читают **ключи** штатного `CombatAudioAlertManager` и конфигурацию; прямые threshold gates `GetPartyBelowCount` | `UNIT_COMBAT` + GUID дружеского юнита + старение оценок; `HealTarget` | JustAC party-only 1–4, зависит от CVar/настроек, UI внутренний: риск обновлений. Для рейда нужен иной способ |
| 11 | Активность восстановления HP | `UNIT_HEALTH` event cadence (`HasSustainedPlayerHealthActivity`) + короткий postcombat grace | История попаданий/лечения | Событие *само по себе* не означает неполное HP — пассивные HoT дают тик даже на полном |
| 12 | HP absorb / shield | `UnitGetTotalAbsorbs`, бинарная проверка нуля | В Sonah прямые/косвенные ауры и defensive state | Точный размер поглощения может быть секретен; только подтверждённый бинарный признак |
| 13 | Точные ресурсы | `UnitPower`, `UnitPowerMax` при доступности, иначе nil | `Units.Power`, `PowerPercent` | [LAZYG] прямое ресурсное значение заблокировано в предыдущих тестах |
| 14 | Ресурс ниже порога | `IsUnitPowerBelow`, `GetPowerBand` через Curve+zero gate | `Curves.PowerBetweenAlpha`, статусные полосы | Отдельные решения (есть ли ресурс на конкретное действие) предпочтительнее «точная мана» |
| 15 | Можно ли оплатить заклинание | `C_Spell.IsSpellUsable`, `C_ActionBar.IsUsableAction`, `ACTION_USABLE_CHANGED`, проверка `noMana` | `Spells.Usable` с `nil` при недоступности | Привязать Slot→SpellID и Rank/Form; режимы usable/mana в GameState отдельно |
| 16 | Combo Points / Holy Power / Chi / shards / руны | `GetClassResourcePoints` читает состояния **живых** стандартных ресурсов-виджетов, включая PRD и nameplate; проверяет регистрацию событий | `Units.ComboPoints` → точный `GetComboPoints` либо оценка генераторов/финишеров | UI-виджеты без live-event могут содержать *устаревшие значения*. Семантика `visualState` отличается у DK и Paladin |
| 17 | Изучено/ранг/таланты/форма | `RotationImport`, `IsSpellAvailable`, `IsPlayerSpell`, `FormCache` и трансформированные ID | `Spells.Resolve`, `Talents`, `Units.Shapeshift*` | Привязать (client,class,baseSpellID,rank,displaySpellID), обновлять при изменении талантов |
| 18 | Кулдаун активен | `GetSpellCooldown().isActive/isOnGCD`, DurationObject `IsSpellOnCooldown` | `Spells.CooldownActive`, `CooldownRemaining` | Флаги могут быть readable при секретном start/duration; валидировать отдельно |
| 19 | Кулдаун длительность | `GetSpellCooldownDuration`, `IsDurationBelowSeconds/Percent`, static base + own-cast history | Static CD, sharedCd и cast log; возвращает estimate/unknown | Получать `active`, estimated remain, timing confidence отдельно; не приравнивать estimate к observed |
| 20 | Заряды/общие CD | `maxCharges`, `isActive`, static cooldowns, `ResolveBaseSpellID`, charges | `Spells.Charges`, sharedCd группы | Проверять charge spells, reset/refund, общие группы, talent modifiers |
| 21 | GCD | `GCDLookahead` дискретные пороги через DurationObject, off-GCD static | `Spells.GCDRemaining` (ID 61304), fallback last successful cast + 1.5s | Текущие 1.5 s в Overlay — DEMO; не выдавать за фактическое значение |
| 22 | Собственные касты и последние действия | `UNIT_SPELLCAST_SUCCEEDED`, `NoteOwnCast`, `WasLastCast`, lastGcdCast | `Spells.NoteCast`, `SinceCast`, target hints, `Casts.Swing` | Plain events позволяют известный факт собственного применения и приблизительную длительность |
| 23 | Каст/канал цели | `UNIT_SPELLCAST_*` target, event state + каст-бар; секретные детали не читать | `Casts.TargetCasting`, `TargetCastKind`, `ApplyTargetCastName` | Разделить «каст идёт», «какой SpellID», «сколько времени», «прерываемый ли» |
| 24 | Прерываемость | `UNIT_SPELLCAST_(NOT_)INTERRUPTIBLE`, Blizzard cast-bar UI, `SetAlphaFromSecretBool` | события + `Curves.BoolAlpha` | UI-приёмник может показать статус, но не доказывает plain bool. Events могут не покрывать начальное состояние |
| 25 | Особо опасные касты | `C_Spell.IsSpellImportant` → `DriveImportantCastAlphas` по каждому nameplate-токену | Прерывание по типу и известным кастам | Светящийся UI-признак ≠ читаемый SpellID; при отсутствии информации «неизвестно» |
| 26 | Бафы/дебафы | `GetAuras`, `RedundancyFilter`, whitelists NeverSecret, `C_Secrets.GetSpellAuraSecrecy` | `Auras.Buff/Debuff`, индекс/ID, snapshot и tracked lookup | `GetAuras` может вернуть список, но *поля* secret, а API по индексу — отказ; не считать пустой ответ отсутствием ауры |
| 27 | Отслеживание ауры в бою | `auraInstanceID→SpellID` вне боя, события added/removed, pending own casts, expiry cache | ID/target epoch/GUID/nameplate/own-cast durée tracking | Сопоставление по времени может ошибиться при одновременно наложенных аурах: нужен quality, epoch и invalidation |
| 28 | DoT на конкретной цели | `DotTracker` own cast + instance add/removal + target swap handling | `Auras` target GUID (когда читается) / nameplate frame / epoch | При секретном GUID нельзя безусловно сопоставить две цели; при потере nameplate лучше `Unknown` |
| 29 | Стаки ауры | `GetAuraApplicationDisplayCount` + `AuraStacksAtLeast`, может ответить только порог | `Auras.Stacks` или estimated stacks по собственным кастам | Раздельно `Known exact`, `AtLeastN`, `Estimated`, `Unknown` |
| 30 | Время жизни бафа/DoT | `C_UnitAuras.GetAuraDuration` → DurationObject и `IsDurationBelowPercent/Seconds`; предбоевой snapshot | `Auras.BuffRemaining/DebuffRemaining`, duration template / cast tracker | Нужны timestamp, expiry, refresh/Pandemic (~30%), факт dispel/early removal |
| 31 | Проки | `C_SpellActivationOverlay.IsSpellOverlayed` / наличие подсветки | `Spells.Overlayed`, trigger history | Прок UI может быть доступен при закрытом численном aura-state, но возвращаемый bool тоже иногда секретен |
| 32 | Дальность | `IsSpellInRange` и `ActionBarScanner` | `Spells.InRange`, range band и несколько проб, `CheckInteractDistance` когда разрешено | Достоверность только относительно конкретного spell/target, не точное расстояние |
| 33 | Количество врагов | `GetEngagedEnemyCount` — nameplate + threat; отдельно assisted-combat/подсказки | `Units.EnemiesNearby/EnemiesInRange`, range estimation | «Бьют меня» ≠ «всего рядом» ≠ «в радиусе конкретного AoE» |
| 34 | Агро/угроза | `UnitThreatSituation` для доступных nameplate | `Units.Threat` / UnitDetailedThreatSituation | Возврат nil может означать отсутствие угрозы или недоступность; учитывать существование цели |
| 35 | Питомец и его способности | `HasActionablePet`, `GetPetStatus`, отказ от pet heal на секретном HP | `Units.HasPet`, `PetHappiness`, `Spells.PetKnownId/PetSpellReady` | Проверить разные классы, Vehicle/Mount, petless talents |
| 36 | Предбоевые бафы/зачарования | `PrecombatEngine`, `MaintenanceTracker`, `GetWeaponEnhancementInfo`, GroupBuffItems | `Auras.WeaponEnchants`, buff tracking | Нужно различать «эффект отсутствует» / «в бою нельзя прочитать» / «активирован раньше» |
| 37 | Тотемы и формы | `IsTotemSlotOccupied`, `FormCache`, UI | `Casts.RegisterTotems`, `Units.ShapeshiftForm` | Тотем слота ≠ нужный тотем; форма/бар переключают наборы действий |
| 38 | Предметы/аксессуары/расходники | `DefensiveEngine`, истории item uses, cost/resource checks | `Items.Count/Usable/CooldownRemaining/Ready` | ItemID, slot, charges, group cooldown и fallback; исключить ложные «готово» при неизвестном |
| 39 | CC / иммунитет / loss of control | `C_LossOfControl`, `UNIT_COMBAT` IMMUNE, `UI_ERROR_MESSAGE`, learned immunity | `Character`, `Casts`, условные gates, история | Индикатор LoC может быть plain, события иммунитета привязаны к недавно применённому CC и цели |
| 40 | Движение/маунт/такси | API движения, `FormCache`, автоатак | `Units.Moving`, `OnTaxi`, `Mounted`, form | Соотнести с cast allowed и instant spell; API может иметь разные secrecy properties |
| 41 | Бой PvP/PvE/рейд/инстанс | `GetContentType` по `IsInInstance`, настройка очередей | `Units.InInstanceGroup`, `InPvP`, `InRaid` | Условия относительно контекста и режима боя, без предположений о секретности |
| 42 | Assisted Combat | `C_AssistedCombat`, GetHighlightCastSpell, Blizzard bar advisory | `Spells.AssistedNext` | Это внешний советчик, **не доказательство**, что собственная XML-ротация выбрала спелл |
| 43 | Клавиши/макросы/слоты | `ActionBarScanner`, MacroParser, `ACTIONBAR_SLOT_CHANGED` | `ActionSlots`, `Macross` | Нужны нормализация SpellID и рангов, видимые макросы и модификаторы, проверка слота |
| 44 | UI-индикаторы и неявные состояния | `UIHealthBar`, `CastInterruptTracker`, Blizzard resource-bar booleans | `Curves` / `Casts.Apply*` / `Alerts` | Данные видны **в UI**, но часто не возвращаются Lua как plain значение |
| 45 | Локализация | JustAC `Locales/ruRU.lua`, `enUS.lua` и др., ID-based mapping | Sonah spell resolution by spellID and lower-case name | На RGB передавать цифровой идентификатор; RU/EN остаются в локальном каталоге LazyG |

## 3. Подробности рисковых механизмов JustAC

### 3.1. Curve + zero-gate (порог HP/ресурса)
- `JustAC/BlizzardAPI/StateHelpers.lua:590–863`: строит пороговую **линейную** Curve с узким переходом (вместо Step); `UnitHealthPercent` / `UnitPowerPercent` отдают результат, который может быть secret; `IsSecretZero` пытается превратить этот результат в **один вопрос** «нулевой или нет»; есть мемоизация на 0.1 секунды, статистика потерь, ограничение размера кэша.
- `JustAC/BlizzardAPI/SecretValues.lua:110–235`: `C_StringUtil.TruncateWhenZero` передаёт секрет в `FontString:SetText`; затем `GetText` возвращает `nil` при нуле по наблюдению автора. Есть проверка `TextReadbackWorks`; автор подробно пишет о возможном скрытом отказе, который нынешняя самопроверка **не распознаёт**.
- В исходнике JustAC прямо сформулировано ограничение: проверять **бизнес-порог**, а не пытаться восстановить скрытый процент сотнями запросов. Это важное отличие от нашего экспериментального набора 5%-клеток, который следует проверить на допустимость и стабильность при новом клиенте. Если механизм пропадёт, `Unknown`.
- В Sonah `Core/Atoms/Curves.lua:35–185` безопасный для Lua вариант *отображения*: установка `Region:SetAlpha` без чтения итогового числа; инструмент исходно применим к визуальным предупреждениям.

### 3.2. Кулдауны, GCD и DurationObject
- `JustAC/BlizzardAPI/CooldownTracking.lua:140–170`: скрытый scratch `Cooldown` получает `SetCooldownFromDurationObject`; затем код проверяет `IsShown`. В комментарии самого JustAC сказано, что это *unintended workaround*, который Blizzard может закрыть.
- `JustAC/BlizzardAPI/StateHelpers.lua:900–956`: `LuaDurationObject:EvaluateRemainingPercent` и `EvaluateRemainingDuration` принимают Curve; результат интерпретируется через zero-gate. Позволяет бинарные вопросы «осталось меньше 3 секунд?» или «ниже 30%» без точного времени.
- `JustAC/BlizzardAPI/CooldownTracking.lua:595–745`: `isOnGCD` и `isActive` из `GetSpellCooldown`; `GCDLookahead` и `ReadyByGCDEnd`; `GetSpellCooldownDuration(spellID,true)` исключает GCD при проверке собственной перезарядки. Есть fallback по базовому CD и событию успешного каста. Коды и флаги относятся к их целевому клиенту, требуют эксперимента на Forever.
- `Sonah/Core/Atoms/Spells.lua:280–438`: GCD ID `61304`, реальное оставшееся время по start/duration, иначе оценка 1.5 сек от `lastAnyCast`; sharedCooldown по группам; `Ready` *optimistic* при неизвестном CD. **Последний приём не копировать для управления клавишами**.

### 3.3. Ауры и DoT, GUID/аураInstanceID
- `JustAC/RedundancyFilter.lua:68–260`: `C_Secrets.GetSpellAuraSecrecy(spellID)` для исключений `NeverSecret`; `auraInstanceID` сохраняется в карту `instance→spell` вне боя, затем `UNIT_AURA` добавляет/удаляет instanceID. Длительность/Pandemic порог вычисляется заранее из plain timestamp. На событии собственного каста ставится pending activation на 2 секунды для сопоставления с аурой.
- `JustAC/DotTracker.lua:1–135`: секретный `UnitGUID(target)` для NPC в бою означает, что глобального надёжного ключа цели может не быть. При `PLAYER_TARGET_CHANGED` трекер очищает/восстанавливает контекст только если может подтвердить связь; не распространять дебаф на другую цель.
- `Sonah/Core/Atoms/Auras.lua:36–130,310–390,420–500,609–735`: target epoch, plain GUID или nameplate-ссылка, собственные касты с duration и отдельный memo. При невозможности идентифицировать возвращённую цель данные об ауре не могут считаться достоверными.
- `JustAC/BlizzardAPI/StateHelpers.lua:955–1030`: бинарное наличие стаков `AuraStacksAtLeast` через engine display function; не равно точному числу стаков.

### 3.4. Здоровье, исцеление, estimators
- `JustAC/BlizzardAPI/StateHelpers.lua:465–592`: `LowHealthFrame:IsShown` иногда вызван **не самим HP**, а fullscreen/flash CVar. Не интерпретировать ALPHA анимации как процент.
- Там же `GetPartyLowCount/IsUnitLow/IsPartyLowAvailable`: штатный аудиоалерт группы имеет внутренние ключи по игроку и `party1..party4`, которые меняются относительно настроенного порога. Данные зависят от включённой функции и не работают как точный raid health.
- `StateHelpers.lua:1657–1810`: `GetPlayerHealthPercent` отдаёт nil при секрете, `GetPetHealthPercent` аналогично; `GetPlayerHealthPercentSafe` возвращает **условные 30% или 100%**, установив `isEstimate=true`; это НЕ измерение. Отслеживает cadence реальных `UNIT_HEALTH` событий и короткое время после боя.
- `Sonah/Core/Atoms/Units.lua:535–910`: оценка HP player/pet через plain `UNIT_COMBAT WOUND/HEAL` и известный UnitHealthMax; оценка здоровья группы по GUID с timeout; оценка NPC по наблюдаемому урону/лечению и известному MaxHP похожих целей. Источник отмечает серьёзные ограничения точности на элитах/боссах и отсутствие событий. В GameState необходимо хранить `Estimated` + интервал доверия/просрочку.

### 3.5. Классовые ресурсы и касты
- `JustAC/BlizzardAPI/StateHelpers.lua:2156–2410`: внутреннее состояние Blizzard class-resource UI (PRD/player/nameplate) как plain `isActive`, `isFull`, `visualState` и т.п. При этом код проверяет, что бар **продолжает обновляться**, используя регистрацию `UNIT_POWER_FREQUENT`/`RUNE_POWER_UPDATE`, иначе значение заморожено. Это не официальная гарантия, и имена рамок зависят от клиента.
- `JustAC/BlizzardAPI/StateHelpers.lua:1870–2105` и `UI/CastInterruptTracker.lua:100–300`: начало и остановка target casts, `UNIT_SPELLCAST_INTERRUPTIBLE/NOT_INTERRUPTIBLE`, UI Shield; первоначальная interruptibility может оставаться unknown даже когда каст идёт.
- `Sonah/Core/Atoms/Casts.lua:1–130`: те же события, безопасная передача названия каста/secret interruptible в FontString/Region; кастинг и название каста — **разные сигналы**.

## 4. Рекомендованный контур для LazyG, без изменения проверенного RGB

1. **Список способностей текущего профиля**: не передавать сотни заклинаний каждый 100 мс. Разделить статический набор (known, rank, talents, baseCD) и live (usable, active, range, proc). Идентификатор `(client, class, SpellID)`.
2. **Версионированные новые RGB-пакеты**, отдельно от действующих v2/v3 и Curve полосы. В каждом пакете: профиль/домен, последовательность, контрольная сумма, часть/количество частей, статус доступности. Ошибка CRC и истечение TTL → Unknown, не False.
3. **HP/Power**: сначала бинарные запросы, соответствующие условиям ротации (20/35/50/70%, ресурс 20/40/70%), и только если их получение разрешено и работает именно на Forever. Источник `Direct`, `UI-visual`, `Estimated`, `Unknown` хранить отдельно. Не полагаться на секретный text-readback как основу без проверки.
4. **AuraTracker**: состояние `(target epoch, confirmed GUID/nameplate if plain, spellID, buff/debuff, source, expiry, stacks)`; события `UNIT_AURA`, собственный `UNIT_SPELLCAST_SUCCEEDED`, target-switch invalidation, периодический контроль.
5. **SpellState**: раздельные learned, usable, insufficientPower, cooldownActive, cooldownRemainingEstimated, charges, inRange, procActive, GCDActive, GCDRemainingEstimated; не сводить всё в единственный `ready`.
6. **CastTracker**: player cast/channel, target cast/channel, event-based interruptibility, отдельный `Known/Unknown` для идентификатора каста, связи с целью и тайминга.
7. **Group/Pet**: наличие питомца, HP категориально/оценочно, состояние членов party; аудиоалерт, internal classbars и скрытые UI-widget приёмы использовать только при наличии подходящего и тестируемого API.
8. **Экран диагностики**: показывать три колонки `Raw source`, `Decoded observation`, `Trust`; кнопки или лог сценариев full HP, damage, target switch, DoT dispel, GCD, charged spell, healer party; все тесты — и в/вне боя.
9. **Гейт рекомендаций**: `Known True` разрешает условие, `Known False` запрещает, `Unknown/Protected/Stale` требует явного fallback; отмечать причины `pause` в Overlay. Не переносить из JustAC/Sonah fail-open допущение, рассчитанное только на рекомендационный UI, в автоматический ввод.

## 5. Что точно ещё не доказано

- Что все заявленные автором JustAC проверки секретных значений воспроизводятся на **конкретном клиенте Forever** пользователя.
- Что получение точного HP/Power/GCD возможно в Lua или RGB во время боя. Успешное рисование UI не доказывает это.
- Что `GetText()` scratch widget, `Cooldown:IsShown`, `CombatAudioAlertManager` или внутренние `visualState` останутся доступными после обновления WoW.
- Что `UNIT_COMBAT` содержит полные и недублирующиеся события урона/лечения в любом контенте, особенно для NPC, питомцев и рейда.
- Что `UnitGUID`, `auraInstanceID` или все поля AuraData одинаково доступны во всех режимах боя.
- Что совет Assisted Combat равен решению будущей XML-ротации.

## 6. Минимальный план проверок на Forever

- A: Вне/внутри боя проверить `issecretvalue`, тип/наличие `UnitHealthPercent`, `UnitPowerPercent`, `UnitHealth`, `UnitPower`, `C_Secrets.*`. Отдельно протестировать HP игрока, цели, питомца и двух членов группы.
- B: В реальном бою проверить ограниченный набор **смысловых порогов** через разрешённые curve-to-widget функции; сравнить с видимым HP без Lua-чтения secret. При недоступном API остановить эксперимент, а не возвращать выдуманное False.
- C: На одном заклинании с обычным CD, одном с зарядами и одном без GCD исследовать `C_Spell.GetSpellCooldown` флаги, DurationObject, события каста; проверить когда GCD начинается/заканчивается.
- D: Баф паладина и метка охотника: применение, повтор, обновление, удаление, смена цели, возврат к первой; проверить `auraInstanceID` / OOC cache / target epoch.
- E: Combo Points в бою, после смены формы и при скрытой стандартной панели; отсутствие живого UI маркировать Unknown.
- F: Target cast start/stop, прерываемый и непрерываемый каст, смена цели; отдельно события и UI-indicators.
- G: Проверить, что ни одна недоступная величина не приводит к ложному `ready/true` или повторному совету без valid target/ability.

**Решение об архитектуре:** текущие источники дают план разработки и набор кандидатов для экспериментов; не подтверждают право считать все игровые секреты доступными и не оправдывают смешение WoW Forever с 3.3.5/Retail.