# LazyG — аудит подключения RGB к XML и Windows (2026-11-19)

**Статус: DEV, не релиз; анализ GitHub `main` и имеющихся пользовательских тестов.** Проверено текущее дерево из 119 GitHub-путей, перечень исходных файлов/тестов/документов и соответствующие архитектурные файлы. Референсные архивы в проекте: `Sertyrew.zip`, `Sonah.zip`, `JustAC.zip`, `Hekili_Forever.zip`, `oharaaster.zip`, `PeonSlayer_addon.zip`; использованы как справочник интерфейсов/подходов, а не как доказательство работоспособности на текущем клиенте. Ранее подтверждённые пользовательские результаты смотрите в `PROJECT_CONTEXT.md`, `CHANGELOG.md`, `RGB_ENGINE.md` и `HUNTER_BM_GAMEPLAY_AUDIT.md`. Сырые пользовательские логи и бинарные архивы в GitHub не копировались.

## 1. Источник истины: что передаётся и что реально проверено

| RGB источник | Доступно в Windows | Статус | Что требуется XML |
|---|---|---|---|
| Forever v2, `Panel.lua` | класс, спек, уровень, позитивные combat/target flags | пользовательские тесты v2 подтверждены | общий `GameState`, не подменять неизвестное `false` |
| Forever v3, `RgbV3Panel.lua` | телеметрия + CRC16 + номер кадра, позитивные flags | direct8 проверен пользователем; stepped4 — синтетический тест | валидированная совместимость профиля/снимка; только подтверждённые факты |
| Forever Curve, `RgbV3Thresholds.lua` | полосы HP/ресурса с шагом 5% | положительные игровые тесты диапазонов | `Observed<HealthBand>`, не точный процент; 0–4% не доказывает смерть |
| LGD, `SpellDiagnosticRgb.lua` | learned/usable/CD/GCD качества для **одного выбранного** SpellID | диагностическое чтение, real-game частично; нет всех rank IDs | плановый spell-state channel по множеству ID, с качеством и TTL |
| LGC, `CooldownRgb.lua` | `SpellActive`, `SpellOnGcd`, `Gcd29515Active`, `Gcd29515OnGcd` и sequence | в игре проверены независимые transitions выбранного CD и 29515 | использовать свежий `Gcd29515Active` как **булево наблюдение**, не `GcdRemainingMilliseconds` |
| LGE, `CastEventRgb.lua` | событие player cast, SpellID, target-change epoch | код/CI; в Hunter-логе 160 Blocked, 0 observed, 182 duplicate; живой сигнал пока не подтверждён | event hint — отдельная диагностика, не результат кастования |
| Будущий SRC | **нет существующего пакета** | архитектура утверждена, но не реализована | источник Internal/Hekili/JustAC, health, seq/epoch, внешняя рекомендация |
| Будущий Aura/Target/Spell batch | **нет готового пакета** | проектировать и проверять | target epoch, presence всех релевантных рангов, выбранные rank/cooldown/usable |

**Подтверждение GCD:** `PROJECT_CONTEXT.md`: 0.2.16 — семь циклов 29515 false→true→false (~1.26–1.57с); 0.2.17 — наблюдался CD13795=true одновременно с GCD29515=false; 0.2.18–0.3 — LGC Lua→RGB→Windows и восстановление подтверждены в игре. ID 61304 оставался Unknown. Эти результаты подтверждают наблюдаемый boolean, а не millisecond duration и не автоматическое разрешение на ввод.

## 2. Выявленные ошибки предыдущей интеграции

1. `RotationFoundation.cs` проверял `GcdRemainingMilliseconds`, тогда как `ForeverCooldownObserver` хранил только LGC boolean. Поэтому вывод `GcdGate=Unknown` возникал даже при наличии рабочего LGC.
2. `/lgprobe hunterranks` сохраняет полный ручной результат только в SavedVariables; эти данные не входят в текущий RGB `GameState.Spells`. LGD и LGC передают выбранный ID, а не полный набор рангов.
3. `TargetDebuffAbsent` требует подтверждённый target epoch и Known(aura) для каждого ранга. `UNIT_AURA` event сам по себе не является доказательством отсутствия/наличия конкретного дебафа. В текущей pipeline полного aura-state нет.
4. `RotationSourceManager` существует как контракт, но полноценного SRC wire, Lua selector и верифицированного переключения нет; `RotationProfileCatalog` содержит только 3 экспериментальных XML профиля, а не полный каталог.
5. В промежуточных коммитах был добавлен отдельный Hunter ARM + SendInput с независимой привязкой F-клавиш и интервалом 1700мс. Это противоречит утверждённому единому исполнителю, общим настройкам и Start/Stop; текущие поля всё равно не позволяют работать. **Удалено из main** с возвратом исходного поведения; историю Git сохранили.
6. Hunter 30 JSON за 05:11:08–05:12:35 UTC: 160/160 Blocked, no expected or observed spells; 182 LGE duplicates. Сводный список missingCapabilities — последняя проверка, а не доказательство, что все 17 сигналов отсутствовали в течение всего боя. Локальный SavedVariables подтвердил конкретные learned rank IDs, но не боевую привязку.

## 3. Правильная единая цепочка

```
Отдельный Lua-адаптер Forever (v2 + v3 + Curve + LGC + будущие типизированные каналы)
  -> 1 снимок foreground bitmap -> независимые проверенные декодеры и freshness
  -> ForeverGameStateBridge: typed Observed(value, quality, timestamp), target epoch
  -> одно универсальное GameState с версионным словарём WoW Forever
  -> InternalXmlRotationSource (XML v2/settings)
       ИЛИ  ExternalRgbRotationSource (проверенный SRC + Hekili/JustAC adapter)
  -> RotationSourceManager (ровно один подтверждённый источник; смена = pause/clear)
  -> общие рекомендации с source, SpellID/rank, target epoch, TTL, reason
  -> единый КОНТРОЛЛЕР исполнения (общие Start/Stop, бинды, задержки, foreground,
       emergency stop, запрет stale/unknown, проверка action kind)
  -> общий event audit, не приравнивать SendInput к успешному касту
```

**Нельзя:** второй исполнитель специально под Hunter; использовать LGD SpellID как рекомендацию; объявлять src READY по v2 profileHash; делать миллисекунды из LGC boolean; считать отсутствие данных отсутствием дебафа; пересылать secret API через обход защиты; переносить GPL код JustAC без отдельного лицензионного решения; смешивать Forever и WoW 3.3.5.

## 4. Выполненные исправления на текущем этапе

- Восстановлены из проверенной code baseline `e224deba...` `MainWindow.cs`, `WowRgbBridge.cs`, `RotationFoundationTests.cs` и test csproj; удалён `HunterExecutionGate.cs`. Автонажатия/ARM из экспериментального пилота отсутствуют.
- `GameState.GcdActive : Observed<bool>` независимо от `GcdRemainingMilliseconds`, с корректным `Age` и три-состоянием. `ConditionEvaluator.GcdReady` читает известный булевый LGC, не синтезируя числовое значение, и сохраняет контракт проверенного числового поля для offline tests.
- `MainWindow.PollBridgeAsync` добавляет свежий проверенный LGC GCD из `ForeverCooldownObserver` в текущий `GameState`. Только если дополнительная передача и приём LGC включены; при потере/заморозке/неизвестном значении GCD не становится готовым. Подключение пока используется лишь для read-only XML/Hunter диагностики, не для отправки клавиш.
- `ForeverGameStateBridge.Diagnostic` раздельно печатает `GCDms`, `GCD29515Active` и итоговый `GcdGate`; C# regression добавлен для true/false/stale/protected и отсутствия выдуманных миллисекунд.

## 5. Следующий законченный инженерный этап (отдельная dev сборка)

1. Подготовить **неизменяемые тестовые векторы** на основании подтверждённых записей v2/v3/Curve/LGC; проверить непрерывность sequence и независимую потерю канала. Сверять с реальной игрой, не только синтетикой.
2. Определить версионированный batch wire для семейства learned rank / usable / cooldown (состояние качества, отдельные обновления и честным TTL), без гонки против UI. Результаты `hunterranks` использовать как проверочный эталон, а не подменять динамические данные.
3. Спроектировать отдельно target epoch и наблюдаемые ауры/debuff (все ранги, явный Unknown, сброс на смене цели). Если Forever запрещает получить поле — явно оставить недоступным; не включать на нём автоматическое действие.
4. Завершить утверждённый SRC wire и переключение источника из Lua миникарты, с верификацией версии provider и no-fallback при потере; внутренние XML без SRC могут работать только в явно подтверждённом Internal mode.
5. Встроить **один** диспетчер/исполнитель клавиш в общие Start/Stop, задержки, привязки и overlay. Положительный результат проверять отдельно; по умолчанию выключено; подключить только после готовности необходимых live states.
6. Расширить Hunter BM ротацию с 4 демонстрационных правил до профильной полноты: pet/aspects, длительные кулдауны, ранги и режимы, сохранив профили разных WoW клиентов в разных адаптерах.

## 6. Критерии приёмки

- CI: Lua 5.1, C# GameState/XML/RGB tests, publish win-x64 single EXE, startup smoke, артефакты EXE и addon **одного run**.
- В игре: при последовательных True→False GCD в Windows видно `GCD29515Active` True→False, при потере фокуса Unknown; при неизвестном rank/aura нет автокаста; полностью проверенные профили позже проходят end-to-end.
- `CI-PASSED` не значит `USER-TESTED`; новый код не является релизом без разрешения пользователя.
