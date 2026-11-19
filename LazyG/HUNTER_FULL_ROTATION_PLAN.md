# LazyG Forever — полноценные ротации охотника: реализация по этапам
**Дата:** 2026-11-19. **Статус:** DEV / архитектура + первый кодовый этап manifest; **не объявлять боевым релизом**. **Цель:** полноценные BM/MM/Survival в PvE/PvP на WoW Forever, начиная с Hunter BM PvE уровня 30. **Основной принцип:** общий Windows EXE, профильно-зависимое наполнение **ОДНОГО** компактного RGB-пакета, отдельный секретный Curve UI-сегмент. Никаких полосок на каждую способность.

## Источники и границы

- **`Sonah.zip/Sonah/Classes/Hunter.lua`** — сверено непосредственное содержимое архива проекта 2026-11-19: 48 703 байта; содержит семейства известных SpellID, правила `levelingPriority`, `bmPriority`, `mmPriority`, Survival, PvP, сложные условия и классовые опции. Использовать как **референс игровых требований и поведения**, не копировать 1:1 чужую реализацию/код и не объявлять авторские симуляционные результаты независимым тестом LazyG.
- **`Sertyrew.zip`** — профильная архитектура передачи (не WoW Forever API): `Profile/Profile.lua`, `Core/Layout.lua`, `Core/Events.lua`, `Collect/Spells.lua`, `Collect/Auras.lua`, `Protocol/{Protocol,Encode}.lua`, `Output/Strip.lua`; см. [RGB_WARMATE_IMPLEMENTATION_PLAN.md](RGB_WARMATE_IMPLEMENTATION_PLAN.md).
- **Текущая кодовая база** — `Engine/RotationFoundation.cs` (XML v2 ограниченные сигналы), `Engine/ProfileDataManifest.cs` (первый новый этап), `Engine/HunterRotationAudit.cs` (известные семейства 4 абилок), `Diagnostics/LazyGForeverProbe` (LGD/LGC/LGE); `AddonTemplate/RgbV3Thresholds.lua` (3 Curve-диапазона с шагом 5%). Проверенная LGC-булевая GCD 29515; не выдумывать длительности.
- Реальные SavedVariables от Hunter уровня 30 подтверждают learned IDs `14323` Mark, `13551` Serpent, `14283` Arcane, `75` AutoShot; **они НЕ передаются в текущий общий live GameState как полный rank batch**. Зависимость от реального уровня/талантов/ранга: через явное состояние, не hardcoded IDs.

## 1. Объём Hunter по классам специализаций

| Режим | Направления из референса Sonah | Состояние в LazyG |
|---|---|---|
| BM PvE, level 30 → 60 | Pet upkeep и наличие; Bestial Wrath/Intimidation по таланту; Rapid Fire; Mark/Sting upkeep, Arcane/Shared cooldown с Summon Hawk, Aimed/MultiShot, GCD, Auto Shot и dead-zone melee | 4 экспериментальные правила; первый manifest для них; реального исполнения нет |
| BM PvP | Scatter/Freezing, Wing Clip, Concussive, Viper, state of target CC и break-on-damage | не реализовано |
| MM PvE/PvP | Aimed/MultiShot shared group, Arcane mana gate, Sniper Shot, Rapid Killing, PvP control | не реализовано |
| Survival PvE/PvP | melee/dead-zone, RaptorStrike/Mongoose, Lacerate, Strider Kick/Counterattack, trap group, Expose Prey proc | не реализовано |
| Общие Hunter состояния | аспект Hawk/Monkey/Beast/Cheetah/Pack/Wild, Trueshot; pet, Mend/Revive, Feign Death/Deterrence, ammo, ranged weapon, movement, target identity/auras, inventory/trinkets, known talents | отсутствует полноценная телеметрия; не угадывать |

**Границы:** Sonah `Hunter.lua` описывает, например, общую группу отката `Aimed Shot / Multi-Shot`, `Arcane Shot / Summon Hawk` и `trap` (после обновлений Forever по словам автора). Конкретная актуальность таймингов проверяется игровым probe, не переносится как доказанный измеренный cooldown. Авторские определения диапазона 8 yd/условий автострельбы — гипотеза для проверки на используемой версии клиента.

## 2. Предварительная матрица сигналов, обязательная для полноценного BM

| Сигнал | Для чего | Где в коде/проекте | Не хватает |
|---|---|---|---|
| identity: client/class/spec/talents | Выбор профиля | RGB v2 / `GameState` | надёжная смена profile schema hash |
| `GcdActive` | Не повторять GCD-команду | LGC 29515 → `GameState.GcdActive` | перенос в compact block и независимая игровая проверка после миграции |
| player/target HP, resource bands | defensives/execute/mana thresholds | `RgbV3Thresholds.lua` Curve | выбранные специализацией адаптивные пороги и корректная проверка цель живёт |
| `SpellFamily` learned rank set | выбирать высший реально изученный | `HunterSpellFamilies`, `hునterranks` | живой profile batch, все используемые в BM способности |
| spell usable / spell cooldown / in-range | основные offensive, pet, CC | LGD/LGC только выбранный spell | профильные флаги для всех spell family IDs + current target |
| targetEpoch и debuff Mark/Sting | не повторять дебаф на другой цели | `RotationFoundation` умеет только evaluate | защищённые aura presence/absence, target reset и quality |
| buffs: current Aspect, procs, rapid/bestial aura | правильная подготовка и burst | референс Sonah | безопасный player aura stream |
| pet exists/alive/health/buffs | pet care, BW, intimidation, mend | WoW v3 имеет pet HP diagnostic, часто Unknown | полноценные pet flags/thresholds |
| moving / casting / auto shot active | не сбивать автоатаку, ranged/melee | `GameState` поля, но нет live связи | проверенные signals + melee/ranged status |
| range / dead zone / ammo / ranged weapon | не стрелять при невалидной дистанции | нет live связи | профильные enum/flags с качеством |
| shared cooldown groups (shot/arcane/trap) | правильный выбор между способностями | частично известны по референсу | компактный group cooldown/scope с прочитанной активностью, не таймер из предположения |
| provider source and single input | Internal/JustAC/Hekili и исполнение | `RotationSourceManager` контракт | подтверждённый SRC и единый input subsystem |

## 3. Последовательность задач (не изменять порядок ради быстрой видимости)

**A. Выполнено в первом кодовом этапе:** `ProfileDataManifestBuilder.Build(profile)` получает из **реального разобранного XML v2** стабильный client/class/spec/mode, упорядоченные base SpellID + полные известные rank IDs, target-aura-family ranks, сигналы GCD/Curve/target. Считает `LayoutHash` для несовместимых profile packets; не содержит физической раскладки пикселей, не требует нового Lua Frame, не отправляет нажатия. Регрессионные тесты проверяют 4 текущих BM правил, 2 дебафа, rank coverage, неизменность schema на изменении порядка правил и изменение хеша при смене набора. **Это контракт данных, не пакет RGB и не полная ротация**.

**B. Следующее:** расширить manifest метаданными всех BM-способностей из собственного исследовательского справочника (source verified, build/quality, ability kind, unit, shared group, range/weapon, pet). Не выдавать Sonah `sp` за доказанный API Forever; применить собственные требования. Разделить `required` vs `optional` при отсутствии secret data. XML parser schema v3 добавить только когда необходима типизация новых условий.

**C. Затем компактный transport:** документировать битовые поля `spellIndex`/aura/state + quality bitmap, target epoch/profileHash, CRC, sequence и геометрию. Это **одна общая область для блока spell/aura/source**, Curve UI protected thresholds отдельно внутри общего геометрического контейнера. Не добавлять LGX-полоски на каждую способность. Нынешний декодер `RgbV3PanelDetector` ожидает *ровно 24/43 physical cells* и `extensionCells=0`, поэтому нужен новый версионированный decoder; прежний нельзя молча переиспользовать для extended packet.

**D. Lua + Windows паритет:** реализовать `ForeverCompat` + profile collector (events/ticks + quality), пакетирование, decoder и `ForeverGameStateBridge`. Тесты pixel+CRC, schema hash, stale, target swap, protected values. Сравнить со старым v2/v3/Curve/LGC в пассивном режиме и подтвердить игровой тест. Приемлем только client-specific capability: отсутствие сигнала означает Unknown, не false.

**E. Полная движковая логика:** самописные BM PvE/PvP, MM PvE/PvP, Survival PvE/PvP XML на новой типизированной схеме, настройки выведены из реально исполняемых правил (не декоративные чекбоксы). Отдельные приоритеты для соло/группы, level gates, Mana5% bands, pet/aspects, CC, shared CD, target aura, dead zone. Добавить собственные тесты с синтетическими пакетами и известными сценариями Hunter.

**F. Последним подключить общий исполнитель:** только один, shared Start/Stop/pause/input key binding/delays, source epoch, не писать класс-специфический SendInput, не слать команды на Unknown, проверять физический foreground и отдельное наблюдение успешного каста. Команда пользователя на игру — **один объединённый dev-архив из успешного run**, не частые промежуточные тесты.

## 4. Критерии окончания Hunter BM PvE

- Встроенный XML содержит настоящие условия поддержания аспектов, HP/мана, PET upkeep, mark/sting, shared cooldown, Aimed/Multi/Arcane/Summon Hawk/AutoShot и emergency/dead zone, а не 4 демонстрационных правила; недоступные сигналы явно обозначены.
- Для всех реально доступных полей есть transport → decoder → GameState → XML тест и лог сохранения/старения; спецификация физически компактна.
- Изученные Hunter ranks и target auras сопоставлены с тем же target epoch, не перепутаны между переходами целей.
- Реальное исполнение проводится только через общий Windows executor, с контролями и журналом; CI + независимый игровой пользовательский тест.
- Никакой новый RGB ряд под один spell/condition, и Curve 5% не становится фиктивным числом.
- Только после BM baseline запускать MM/SV, не смешивая разные WoW клиенты.

## 5. Следующий чат

Сначала прочитать `PROJECT_CONTEXT.md`, `CHANGELOG.md`, `RGB_WARMATE_IMPLEMENTATION_PLAN.md`, **этот файл**, `RGB_INTEGRATION_AUDIT.md`, актуальные GitHub `main` файлы `ProfileDataManifest.cs`, `RotationFoundation.cs`, `HunterRotationAudit.cs`, `Rotations/Forever/Experimental/hunter-beast-mastery-pve.xml`. Сверить архивы `Sonah.zip/Sonah/Classes/Hunter.lua` и `Sertyrew.zip/Profile/Profile.lua`, `Sertyrew.zip/Protocol/`, `Collect/`, `Output/`. Продолжать с **Шага B → C**, не начинать с нуля и не переписывать проверенные RGB или отдельный ввод. Обновлять код, CI и документацию, сохранять rollback. Первый milestone ещё не полная Hunter BM ротация.
