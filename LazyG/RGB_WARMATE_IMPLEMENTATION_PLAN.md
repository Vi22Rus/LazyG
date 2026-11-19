# LazyG — УТВЕРЖДЁННАЯ архитектура RGB → GameState → XML по модели WarMate/Sertyrew
**Дата решения:** 2026-11-19. **Статус:** [USER APPROVED / DESIGN ONLY / NOT IMPLEMENTED IN FULL]. **Первый клиент:** WoW Forever. **Репозиторий:** `Vi22Rus/LazyG`, `main`. **Это обязательная точка входа при продолжении разработки после смены чата.**

## 0. РЕШЕНИЕ ПОЛЬЗОВАТЕЛЯ — НЕ ТЕРЯТЬ ПРИ СМЕНЕ ЧАТА

1. Архитектурный образец: **WarMate Windows EXE + Sertyrew Lua**. Перенять профильно-ориентированное описание данных, разделение сбора/кодирования/решения, универсальную схему пакета, CRC, свежесть кадров и единый исполнитель. Сами закрытые решения WarMate Windows не являются доступным исходником.
2. **Не плодить RGB-полоски.** У LazyG уже есть v2, v3, длинная 62-ячеечная Curve плюс LGD/LGC/LGE диагностика. Нельзя на каждое новое поле, класс, способность или источник ротации добавлять отдельную физическую строку. Требуется компактное профильное расширение в **одном логическом RGB-транспорте**, по возможности в одной компактной экранной области/одном кадре захвата.
3. **Нельзя ломать то, что реально проверял пользователь.** Существующие v2/v3/Curve/LGC не менять и не удалять до доказанного параллельного теста нового формата, CI, игрового теста и явно согласованного перевода. Пока оба протокола нужны для сравнения/отката.
4. **В WoW Forever защищённые HP/ресурсы** нельзя произвольно превратить в обычное число. Нынешние 62 Curve-пикселя не «ошибка, которую легко сжать»: 19 threshold-битов + status на каждый из трёх показателей (HP игрока, HP цели, ресурс) формируются защищённым UI-механизмом. Нельзя просто прочитать из Lua результат и закодировать одним байтом. У 3.3.5 прямые числа доступны иначе. Оптимизировать Curve **только после самостоятельной проверенной альтернативы**; не выдавать сжатие за готовое решение.
5. Один C#/.NET 8 Windows EXE (актуальная сборка **Avalonia**, долгосрочная цель WPF обсуждалась отдельно), отдельные версии Lua для Forever/3.3.5, отдельные XML-ротации, универсальное Windows-ядро. Lua передаёт наблюдения, Windows считает внутренние XML-ротации. Переключение Internal/Hekili/JustAC через Lua-иконку миникарты и подтверждённый RGB-статус по `ROTATION_SOURCES_PLAN.md`.
6. **Никаких специальных исполнителей по классам.** Единственный исполнитель Start/Stop, mapping, задержки, безопасность, emergency stop для всех источников. Несовершенный эксперимент Hunter F-key ARM/SendInput ранее откатан.
7. Статусы [GAME-TESTED], [CI-PASSED], [PLANNED] держать отдельно. Следующий запрос на код — одним завершённым dev-пакетом, а не множеством промежуточных пользовательских ручных испытаний.

## 1. Точные референсы: что открыть перед кодированием

**Архивы в файлах проекта Lazy:** `Sertyrew.zip` (69 ZIP entries включая папки; путь внутри `Sertyrew/`), `WarMate.zip` (содержит **`WarMate.exe`**, бинарный референс, исходников Windows-части нет). Оба архивных источника физически перепроверены 2026-11-19. Не реконструировать их из памяти. При наличии других файлов/архивов поддержки: `warmate-support-20261119-094139.zip`, `Sonah.zip`, `JustAC.zip`, `Hekili_Forever.zip`, `oharaaster.zip`, `PeonSlayer_addon.zip` — дополнительный анализ только по конкретной задаче.

| Файл внутри `Sertyrew.zip` | Реально наблюдаемая роль | Что использовать в LazyG |
|---|---|---|
| `Sertyrew/Protocol/Protocol.lua` | `version=1`, 23 core cells, 5 plain cells, CRC16, `direct8`/`stepped4`, перечень fields/blocks | Определение логического protocol schema; НЕ копировать WoW 3.3.5 поля как Forever-API |
| `Sertyrew/Protocol/Encode.lua` | `NewLayout`, описание/компоновка snapshot, `logicalCells`, `physicalCells`, `rows`, RGB+checksum | Layout manifest и детерминированный packing/CRC, версионность |
| `Sertyrew/Protocol/Crc16.lua`, `Bits.lua` | CRC16 и битовые поля | Сверить тестовые векторы и пределы; собственная C#/Lua реализация |
| `Sertyrew/Core/Layout.lua` | Применение профиля, заполнение/сброс snapshot, `MapAbilities`, расчёт `maxProfileCells` | Reset при смене класса/спека и отсутствие старых состояний |
| `Sertyrew/Profile/Profile.lua` | `WML_PROFILES`, `abilities`, `auras`, `blocks`, `buttons`, `gcdReference` | Registry требований профиля (ключи/ранги/семейства), но не копировать 3.3.5 SpellID на Forever |
| `Sertyrew/Core/Events.lua` | `Area(name, interval, refresh, tick, events)`, dirty по событиям, `Step` | Обновление данных по событиям + периодически, без спама вызовов API |
| `Sertyrew/Collect/Player.lua` | player/vitals, GCD через профильный `gcdReference` или 61304 | Сам **паттерн ссылки на GCD**, но не 61304 для Forever |
| `Sertyrew/Collect/Target.lua` | target/flags/cast/attributes и смена цели | Факты и идентичность цели, сброс старого target state |
| `Sertyrew/Collect/Spells.lua` | профильный набор ability cooldown, known, usable, range, condition flags | Профильные SpellState по реально доступным сигналам |
| `Sertyrew/Collect/Auras.lua` | массив аур профиля, `remaining/stacks/unknown`; отдельная обработка target debuff | Ауры с качеством Unknown и корректной сменой цели |
| `Sertyrew/Output/Strip.lua`, `FrameAnchor.lua` | размещение пикселей, scale, multiple rows, painting, `OnUpdate`, frame counter | **Одна компактная геометрия**, логический кадр, layout по фактическому physical pixel scale |
| `Sertyrew/Bind/AutoBind.lua`, `VirtualButtons.lua` | игровая привязка, `SecureActionButtonTemplate`, ограничение изменения во время боя | Референс безопасной системы общего биндинга, не копировать напрямую в Forever |
| `Sertyrew/Compat/Api335.lua` | клиентский API-адаптер 3.3.5 | Отдельный ForeverCompat/335Compat, без смешения API |
| `WarMate.exe` из `WarMate.zip` | Windows бинарь, исходники недоступны | Референс продукта и поведения; нельзя утверждать точные внутренние функции Windows без отдельной доказательной базы |

**Важное уточнение:** у Sertyrew `Profile.lua` хранит список требуемых полей; это **не доказательство**, что его приватная Windows-часть использует те же XML-правила, что задуманы в LazyG. Доказана Lua-архитектура, а не внутренности WarMate.exe.

## 2. Что уже подтверждено в LazyG и должно быть сохранено

- `LazyG/AddonTemplate/Panel.lua`: v2 identity, 9 ячеек, якорь (0,0); проверено пользователем в игре.
- `LazyG/AddonTemplate/RgbV3Panel.lua` + `RgbV3Encoder.lua`: direct8 v3 24 ячейки при y≈12, CRC; `stepped4` в C# декодере синтетически тестировался, но не в WoW. Действующий `RgbV3PanelDetector.cs` **ожидает только нулевые extensions и 24/43 физические ячейки** — это важнейшая точка до изменения wire/layout.
- `LazyG/AddonTemplate/RgbV3Thresholds.lua`: отдельная Curve строка 62 ячейки при y≈24, 4×4 UI + 1 промежуток; **физическая ширина при pitch 5 ≈309 UI единиц**, не обязательно 309 физических пикселей при UI Scale; формирует 3 группы × (status + 19 binary thresholds) + 2 marker cells.
- `LazyG/Diagnostics/LazyGForeverProbe/{SpellDiagnosticRgb.lua,CooldownRgb.lua,CastEventRgb.lua}`: LGD y≈65, LGC y≈76, LGE y≈87, по 6 ячеек каждый; это **диагностика**, не рекомендуемый постоянный способ расширять ротационный wire.
- `LazyG/Windows/WowRgbBridge.cs`: захват одного `Bitmap` до 800×120 физических пикселей, **только foreground WoW**; нельзя менять якоря/масштаб, не перепроверив захват и детекторы.
- `LazyG/Avalonia/ForeverGameStateBridge.cs`, `Engine/GameState.cs`: типизированные Known/Unknown/Protected/Stale; `GcdActive` (LGC `29515.isActive`) добавлен как отдельный boolean, а не fake duration.
- В игровых тестах `29515.isActive` даёт интервалы GCD; `61304` оставался Unknown. CD выбранного spell и GCD различались. Нет полного потока Learned/Usable/CD каждого rank + аур всех рангов + target epoch; `/lgprobe hunterranks` в SavedVariables — **не** живой RGB batch.
- `LazyG/Avalonia/Engine/RotationFoundation.cs`: XML v2 и проверка условий; `RotationSourceManager` пока без живого SRC; `RotationProfileCatalog.cs` пока содержит 3 experimental профиля. **Никакого действующего общего auto-input**.
- Проверенный исходный code baseline: [GitHub Actions 44465707808](https://github.com/Vi22Rus/LazyG/actions/runs/44465707808) SUCCESS на коммите `06ef3793f5633e45b21cce1d55a88083f11602bd`; артефакты Windows `14501488795`, Lua `14502071739`; CI ≠ игровая проверка нового адаптера. Rollback перед LGC↔GameState: [44462581902](https://github.com/Vi22Rus/LazyG/actions/runs/44462581902).

## 3. Важное архитектурное решение о длинной Curve и количестве полос

### 3.1. Не приравнивать логический пакет к физической строке

**Нужен один расширяемый протокол, а не десятки UI-полосок.** Логически кадр содержит Header, core, профильные Spell/Aura/Source/Target блоки и CRC. Физическое отображение может занимать **одну компактную область с рядами**. Новые поля **не обязаны** порождать новые независимые `Frame` на новых y-координатах. Geometry/anchor/scale — отдельный слой.

### 3.2. Почему нельзя сразу убрать 62 Curve-ячейки

В Forever пороги 5% формируются через `UnitHealthPercent/UnitPowerPercent` + `C_CurveUtil` и применение результата непосредственно к `Texture:SetAlpha`. Это **UI-путь передачи секретного значения**. Lua не получает обычное число `HP=63`; значит, нельзя без исследования заменить 19 защищённых бинарных порогов одним байтом. Иначе сломаем пользовательски проверенные HP/ресурс. У WoW 3.3.5 `Compat/Api335.lua` другой тип доступности — число может передаваться компактно, и это *другой клиентский адаптер*.

**Допустимая оптимизация:** изучить безопасное распределение Curve-пикселей в **общем прямоугольнике**, уменьшить декоративные промежутки/настроить anchor/scale (проверив реальный захват), либо обоснованно сократить число порогов с согласованной потерей точности только после реального Forever теста. Варианты: многофазное последовательное измерение меньшим числом ячеек (влечёт время/синхронизацию/скачки HP), profile-specific пороги (может потерять универсальные 5% диапазоны), Curve native опыты (не доказано). **Не реализовывать ни один вариант без теста**, не обещать одновременное 5% разрешение в меньшем числе ячеек.

### 3.3. Миграция физического расположения без «третьего экрана»

**Этап 1:** оставить все старые физические ряды в привычных местах. Добавить только **проект/прототип** нового объединённого layout, замеры bounding rectangle, конфликты при разном WoW UI Scale и при 800×120 скриншоте. Новый protocol identifier, schemaVersion и логический profileHash; фиксированный budget ячеек/физических рядов до реализации.

**Этап 2:** один `LazyG RGB Compact Frame` с оптимизированной геометрией и профильно-описанными данными. Curve-пороги остаются отдельным визуальным subregion в **этом же геометрическом контейнере** (если API допускает такое расположение), но не кодируются как обычные RGB-байты. Регулярные поля упаковать плотно в один schema-driven bitstream, не в собственную диагностическую полоску каждого поля. Референс: `Protocol.lua`+ `Encode.lua` + `Output/Strip.lua` Sertyrew. Дублирование v2/v3 в новом runtime **после доказанной миграции** убрать, не раньше.

**Этап 3:** после одновременного параллельного игрового сравнения на нескольких DPI/UI Scale и повторной проверки CRC/Curve пересмотреть удаление временных диагностических LGD/LGC/LGE (или скрыть их в Debug Mode). Только по согласованной процедуре отката. Цель — **минимальная экранная площадь**, не формальный минимум количества Lua frames.

**Обязательно промерить:** реальное положение рамки, максимально допустимые width/height с запасом, физический шаг, движок WoW UI scale, windows client crop и latency. Не предполагать, что изменение RGB-схемы автоматически ускоряет сканер; обновить сам декодер.

## 4. Целевая цепочка Windows (строго по слоям)

```text
WoW Forever Lua Adapter
  API Compat + Profile Data Manifest (из требований XML, не lua-ротация)
  Collect Core / Curve protected UI thresholds / Spells / Auras / Target / Source
  Event-driven refresh + bounded ticks + field quality/availability
      ↓
Compact RGB Layout (version, clientID, profileHash/layoutHash, frameCounter,
                    per-block quality, targetEpoch, payload, CRC)
  Curve — отдельный UI-сегмент в той же компактной визуальной области
      ↓ ONE screenshot foreground WoW
LazyG Windows RGB Receiver
  calibrate markers, physical layout and scaling
  validate CRC, layout identity, sequence, age, channel consistency
  parse typed profile blocks, keep field quality + source timestamp
      ↓
ForeverGameStateBridge -> universal immutable GameState
  (with Known/Unknown/Protected/Stale, spells by concrete rank ID,
   target-epoch keyed aura info and health bands)
      ↓
RotationSourceManager: choose EXACTLY ONE verified source
  Internal: XML V2 + settings / External: SRC provider recommendation
      ↓
Single rotation action / shared key binding / Start-Stop / delays
  (only when fully supported; no class-specific execution loop)
      ↓
Execution telemetry separated from observed WoW cast/effect events
```

**Инвариант:** XML/Windows rule engine не знает положения RGB-пикселей, Curve textures или CRC. Windows UI не превращает невалидные RGB в Known. Lua не принимает решений о приоритете внутренней ротации.

## 5. Подробный план внедрения — следовать именно этому порядку

### Шаг 0 — инвентаризация без кода

Открыть `PROJECT_CONTEXT.md`, `CHANGELOG.md`, **этот план**, `RGB_INTEGRATION_AUDIT.md`, `RGB_ENGINE.md`, `ROTATION_SOURCES_PLAN.md` и актуальные файлы `main`. Сверить `Sertyrew.zip` из файлов проекта с разделом 1. Составить таблицу **user-game-tested / CI-only / proposed** по каждому полю, **с обязательным указанием клиентской версии**. Никаких правок прежнего v2/v3/Curve пока нет.

### Шаг 1 — «manifest» входных данных для XML профилей

Для каждого WoW-client/class/spec/mode и версии XML вывести список потребностей: базовый GCD, цель (liveness/hostility/epoch), HP/resource thresholds, семейства/ранги SpellID, их usable/CD/learned, список аур/дебафов с provenance и целевым epoch, pet, range/casting. Определить неизменяемый `ProfileDataManifest` с `clientId`, `schemaVersion`, `profileHash`, `spellIndex→concreteSpellId`, `auraIndex→unit/ids`, `blockCapabilities`. Несовместимость — явная ошибка; не оценивать XML чужого клиента. Референсы Sertyrew `Profile/Profile.lua`, `Core/Layout.lua`; LazyG `RotationProfileCatalog.cs`, `RotationFoundation.cs`.

**Тест:** только 4 правила Hunter BM имеют собственные требования, не требуют всех классов/заклинаний одновременно; полный набор из узнанных игровых рангов распознаётся как профильные данные, а не только лог SavedVariables.

### Шаг 2 — компактный wire-дизайн (документ перед кодом)

Определить полную byte/bit схему с magic/version, client-adapter build, layout/profile hash, sequence, target epoch, quality/availability bitmap, длиной/типами фиксированных блоков, CRC. Определить лимит ячеек на профиль, запас на расширения, хеш и compatibility negotiation, reserved fields и варианты частичного snapshot. Сравнить `direct8` и `stepped4` по реальным пикселям и возможному repaint/blur; **не допускать перезаписи существующих v3 ячеек до bump версии**. Рассчитать физический rectangle, число рядов и Curve segment отдельно. Референс Sertyrew `Protocol/Protocol.lua`, `Protocol/Encode.lua`, `Core/Layout.lua`, `Output/Strip.lua`.

**Важный технический факт:** `RgbV3PanelDetector.FindPanel` сегодня вызывает `RgbV3Codec.TryDecode(..., extensionCells:0, expectedProfileHash:0x4C47)` и жёстко ждёт 24 или 43 ячейки. Одного расширения Lua недостаточно: новый receiver должен валидировать layout и profile hash, а не читать изменённую длину старым детектором.

### Шаг 3 — Forever Data Collector без увеличения числа полос

Разнести Lua в `ForeverCompat`, `Collect/Core`, `Collect/Spells`, `Collect/Auras`, `Collect/Target`, `Transport/Encoder`, `Transport/CompactStrip` (рекомендуемая структура, не текущие имена). События инвалидируют cache, `OnUpdate` обновляет bounded tasks. **Не вызывать WoW API на каждый RGB-пиксель.** Secret/API errors — quality flags, `Unknown` не равно `false`. Для CD/GCD повторно использовать проверенный LGC `29515.isActive` как типизированное поле. Не обобщать 61304 из 3.3.5. CURVE остаётся сохранённым рабочим subregion. Ауры и target epoch проверять отдельно в живом клиенте; событие `UNIT_AURA` само по себе не доказывает presence.

**Тест:** WoW Lua 5.1 mock, неверные secret fields, обновление spell state после события, неизменность старого Curve/CRC и отсутствие новых экранных полосок на каждую ability.

### Шаг 4 — Windows Capture → Decoder → GameState

Оставить `WowRgbBridge` единым вызовом захвата и конкретный detection по session client. Новый compact decoder должен читать **layout/schema**, CRC, sequence, profile hash, class/spec и timestamp; критический invalid frame должен давать Unknown, не carry-over старой рекомендации. Read-only параллельный режим compare старого и нового: раскладка targets/HP/Curve/GCD/Spells; не смешивать кадры разных target epochs. Нормализовать в `GameState` через `ForeverGameStateBridge`, НЕ напрямую в XML и не в `MainWindow` логику ротации. Перенести временные поля из UI polling в централизованный adapter только после регрессий.

**Тест:** loss/recovery, stale 1.2/1.5s по каналу, CRC, смена профиля в бою/вне боя, частично protected aura, target change, foreground loss, различие false/unknown, два WoW клиента в каталоге (без смешения данных).

### Шаг 5 — решить длинную Curve *по факту измерений*

Измерить реальную геометрию 62-ячеечной строки, занятое место и возможности переставить в один Compact Frame **без нарушения разрешённых UI secret-путей**. Сравнить базовую версию и 1–2 альтернативы по точности 5%-полосы, latency, CPU, длине экрана и работе при DPI/UI Scale. Если выигрыш не доказан — **оставить 62 ячейки**, но компактно разместить с остальными как одну визуальную область. Не терять проверенный 5% канал ради косметики. В 3.3.5 использовать другой числовой формат, а не Forever Curve.

### Шаг 6 — source selector и единый исполнитель

Следовать `ROTATION_SOURCES_PLAN.md`: Lua minimap right-click Internal/Hekili/JustAC, передать `DesiredSelection` + `ProviderHealth` + sequence/epoch + при external режиме проверенный recommendation SpellID как **типизированный block одного нового transport**, а не ещё одна отдельная физическая полоса SRC. `RotationSourceManager` инвалидирует старую рекомендацию на смене источника; при ошибке внешнего аддона **не** переключаться на Internal автоматически. Затем подключить единую подсистему исполнения с общими keybinds/delays, Start/Stop, foreground, Pause/EmergencyStop, source epoch; никаких F-key Hunter pilot.

**До появления полноценного live spell/target/aura evidence и общего исполнителя — только read-only рекомендации**. Выданная клавиша не равна успешному касту.

### Шаг 7 — комплексное подтверждение, выпуск dev и откат

После **одного объединённого** dev-пакета: GitHub Actions Lua mock, C# unit/decoder+snapshot tests, real Windows .NET 8 win-x64 single-file publish, smoke, **два артефакта из того же run**. Пользовательский тест Forever только после успешной интегрированной сборки: CRC/sequence, 5% bands, GCD True/False, learned concrete ranks, target epoch, дебафы, переключение источника, потери фокуса, stale/rollback. Отдельно фиксировать screenshot geometry, несовместимость секретов, результат исполнения и независимое событие WoW. **Не объявлять релизом**, пока пользователь не подтвердит. Указать ссылку на успешный CI и PowerShell publish.

```powershell
dotnet publish .\LazyG\Avalonia\LazyG.Avalonia.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o .\publish
```

## 6. Критерии «не плодим полоски» — обязательные acceptance

- Новая ability или aura **не добавляет отдельный физический RGB Frame**; она добавляется в профильный manifest и общий packet layout.
- Новый source Internal/Hekili/JustAC **не добавляет отдельный RGB Frame** после перехода на compact wire; он кодируется типизированным блоком.
- Защищённые Curve thresholds **не конвертируются из Lua в обычные числовые байты** без независимого игрового подтверждения.
- До переезда не менять физические координаты и API проверенных v2/v3/Curve/LGC; в миграционном сравнении экранная площадь может кратковременно возрасти, но **не считать такое размещение целевым**. Для dev использовать переключаемые старый/новый layout, не отображать всё одновременно по умолчанию.
- Явно измерить *физическую суммарную площадь*, а не только число полосок.
- Любое новое поле имеет source/client/profileHash, data quality и age; `Unknown` не разрешает автоматический каст.
- Проверка после смены класса/spec/цели/source обязана инвалидировать старые данные.
- Никаких случайных игровых действий из Lua collector и никакой отдельной Hunter-ветки input.

## 7. Что НЕ сделано и не должно быть домыслено в новом чате

- Полноценный compact RGB frame **не реализован**. Данный документ — решение/спецификация работ.
- Длительность GCD в ms остаётся неизвестной: проверено только bool 29515. Нельзя смешивать GCD 335 и Forever.
- Обнаруженные в SavedVariables ранги Hunter 30-го уровня не превращены в live SpellState всех рангов.
- Полный pipeline aura+target-epoch и SRC provider ещё нет. Правильная Windows XML и общая клавиатурная система ещё не умеют действовать в игре.
- Точная внутренняя реализация Windows `WarMate.exe` неизвестна; Sertyrew Lua inspect позволяет обосновать только Lua-протокол/сбор/вывод/биндинг.
- Любые сокращения Curve или упаковка secret data — гипотезы до CI и in-game испытания.

## 8. ПЕРЕДАЧА В НОВЫЙ ЧАТ

Прочитай из GitHub ветки main **`LazyG/PROJECT_CONTEXT.md`**, **`LazyG/CHANGELOG.md`**, затем **`LazyG/RGB_WARMATE_IMPLEMENTATION_PLAN.md`** (этот документ), **`LazyG/RGB_INTEGRATION_AUDIT.md`**, **`LazyG/RGB_ENGINE.md`**, **`LazyG/RGB_PROTOCOL_V3_SPEC_DRAFT.md`**, **`LazyG/ROTATION_SOURCES_PLAN.md`**. Открой актуальные source files `LazyG/AddonTemplate/`, `LazyG/Diagnostics/LazyGForeverProbe/`, `LazyG/Windows/WowRgbBridge.cs`, `LazyG/Windows/RgbV3Codec.cs`, `LazyG/Windows/RgbV3PanelDetector.cs`, `LazyG/Avalonia/ForeverGameStateBridge.cs`, `LazyG/Avalonia/Engine/`. Затем **перечитай архив `Sertyrew.zip` из файлов проекта** (таблица раздела 1), а `WarMate.zip` трактуй как бинарный референс. Сразу продолжай с **Шага 1: ProfileDataManifest + компактный layout design**, **не создавая дополнительных постоянных полосок**. Не вноси код без нового прямого запроса; при работе кодом фиксируй CI/rollback/docs и dev-only статус. Существующий пользовательский RGB и Curve **не ломать**.
