# Углублённый аудит Sonah Forever 1.2.5 — взаимодействие с Blizzard API

Источник: непосредственно предоставленный архив Sonah.zip, Sonah.toc (Interface 16001), Core/Atoms, Core/Molecules, Core/Organisms и Classes/Hunter.lua. Дата: 2026-11-20. Только WoW Forever, не 3.3.5. Подробный 25-раздельный полный отчёт на 42 КБ передан пользователю отдельным файлом SONAH_FOREVER_API_DEEP_AUDIT.md в этой беседе. Здесь зафиксирована проверенная карта API и план внедрения.

## 1. Защищённые значения
Файл Core/Atoms/Secret.lua 1–259. issecretvalue/issecrettable/canaccessvalue плюс pcall: secret сохраняет обычный type, но его нельзя сравнивать, складывать и использовать в if. Call/CallMulti/CallAt/CallNumber/CallBool/Field/Fields/FieldNumber пропускают лишь разрешённые значения; nil значит Unknown. Raw/RawField только для передачи значения разрешённому widget-методу. C_Secrets.ShouldAurasBeSecret и ShouldCooldownsBeSecret дают актуальный режим, HasSecretRestrictions лишь build-capability. BeginEpoch/EndEpoch/Memo — кэш в рамках одного расчёта. В LazyG нужен общий ForeverSecretSafe и происхождение каждого сигнала.

## 2. Чтение аур
Core/Atoms/Auras.lua ~127–263,~680–736. C_UnitAuras.GetAuraDataBySpellName с множеством имён (локализованное, C_Spell.GetSpellName, def.aura, имена талантов); игроку GetPlayerAuraBySpellID. Из безопасных expirationTime/duration/applications вычисляются remaining/stacks/duration с source=api. По умолчанию HARMFUL|PLAYER — свои дебафы, def.any — чужие тоже. При секретности nil результата не значит отсутствие; только полностью доступный поиск с известной открытой секретностью допускает false. В LazyG пока нет SourceMine, стаков и времени.

## 3. Успешные касты и цель
Core/Atoms/Spells.lua ~830–1100. UNIT_SPELLCAST_SENT фиксирует предполагаемый адресат/castGUID, UNIT_SPELLCAST_SUCCEEDED от player фиксирует lastCast/lastAnyCast, PLAYER_CAST публикует событие, C_Spell.GetBaseSpell связывает talent override. SENT и Logitech IOCTL не доказывают успех; SUCCEEDED не доказывает попадания и наложения дебафа. Для лечения сопоставляются GUID членов группы, target, mouseover, focus и cast target hints. LazyG теперь применяет ограниченный Hunter-кэш SENT/SUCCEEDED.

## 4. Скрытые ауры и per-mob история
Core/Atoms/Auras.lua ~34–118,~285–470,~610–690. Auras.Track сохраняет time+duration+target epoch+GUID+nameplate object; OnThisTarget сопоставляет идентичность; other targets хранятся ограниченно, при NAME_PLATE_UNIT_REMOVED удаляются frame associations, при PLAYER_REGEN_ENABLED очищаются guesses. Прямой API ответ имеет преимущество над предсказанием. Lua object nameplate нельзя переслать указателем через RGB; для универсального Windows-ядра нужен отдельный временный непрозрачный TargetToken и TTL. Текущий Hunter epoch-only fallback при возврате к старой цели пока теряет историю.

## 5. Дебафы и DoT refresh
Core/Molecules/Conditions.lua ~375–474, Classes/Hunter.lua ~35,41,~191–212. debuffMissing при Unknown читает Spells.SinceCast и Auras.Duration; Hunter's Mark=120 секунд, Serpent Sting=15 секунд. dotRefresh оценивает clipping тиков, текущий GCD, каст и filler, а не только наличие. Для LazyG XML пока поддерживает лишь TargetDebuffAbsent и cast-event fallback; Remaining/Stacks/RefreshWindow ещё нет.

## 6. Кулдауны и GCD
Core/Atoms/Spells.lua ~280–409. C_Spell.GetSpellCooldown(61304) даёт startTime/duration при доступности, отдельно isActive/isOnGCD; когда временные поля секретны, Sonah оценивает GCD от lastAnyCast+1.5 секунды. Переносить фиксированный 1.5-секундный GCD сейчас не следует: пользователь отложил. Отдельные CD считаются по доступному времени, а когда скрыты — по def.cd и последнему успешному касту. sharedCd группы учитывают любого участника; isActive=true не позволяет объявить кнопку готовой по истёкшему прогнозу. LazyG имеет лишь частичные булевы CD и UI-взаимоисключения, но не настоящий sharedCd runtime.

## 7. Изученность, пригодность, ресурсы и заряды
Core/Atoms/Spells.lua ~70–280,~395–445,~800–840. C_Spell.GetBaseSpell/GetOverrideSpell/GetSpellName, IsSpellUsable, GetSpellCharges, Known конкретных рангов; отдельный notEnoughMana, GCD slack. Sonah оптимистичен в рекомендациях при некоторых Unknown; Windows HID не должен автоматически перенимать эту политику. В LazyG Hunter Compact уже передаёт learned rank, usable, cdActive, но нет общего registry по всем классам, charges и talent overrides.

## 8. Дистанция и dead zone
Core/Atoms/Spells.lua ~445–800; TalentRangeData.lua; Core/Organisms/Engine.lua ~310–349. C_Spell.IsSpellInRange может вернуть nil, тогда Sonah применяет probes других способностей той же полосы, C_Spell.GetSpellInfo min/max диапазоны, CheckInteractDistance и талантные изменения range, не применяя модификатор дважды. Для Hunter отдельный min range и melee dead zone. strictRange может пропустить ability; нестрогий выбор подсвечивает outOfRange красным. В LazyG поле InRange пока не заполняется RGB и не блокирует HID: это приоритет P0.

## 9. HP, ресурсы, визуальные curves
Core/Atoms/Units.lua ~320–520,~650–965; Curves.lua ~1–275. UnitHealth/Max/Percent, UnitPower/Max/Percent/Type с проверкой secret; при закрытых данных Sonah использует события и estimates (отдельная политика для обычных мобов и боссов). C_CurveUtil.CreateCurve, UnitHealthPercent(unit,true,curve), передача secret прямо в UI widget допускают отображение без извлечения числа. Из этого НЕ следует право читать секрет в Lua или кодировать его через RGB. LazyG имеет coarse 5%-band, требует типизированных ресурсов и provenance.

## 10. Цели, AoE и групповая идентичность
Core/Atoms/Units.lua ~40–320,~970–1115; HealTarget.lua. UnitExists, UnitIsDeadOrGhost, UnitCanAttack, UnitGUID/UnitTokenFromGUID, C_NamePlate.GetNamePlates, UnitIsUnit и group units; нет nameplates ≠ ноль врагов. При исцелении нужно знать конкретного адресата каста и отделять Unknown от healed member. Lua и Windows должны сохранять scope цели, а не один общий target без identity.

## 11. Касты цели и прерывания
Core/Atoms/Casts.lua ~1–135. UnitCastingInfo/UnitChannelInfo могут быть secret, но UNIT_SPELLCAST_START/STOP/FAILED/INTERRUPTED/CHANNEL_START/STOP и INTERRUPTIBLE/NOT_INTERRUPTIBLE дают событийную информацию, с отдельной защитой от пропущенного stop. Engine HoldChannel умеет удерживать своё channel и пропускать только emergency/interrupt. В LazyG этих сигналов в RGB пока нет.

## 12. Автоатака, swing и Auto Shot
Core/Atoms/Casts.lua ~140–237; Classes/Hunter.lua ~212–235. PLAYER_SWING(duration,swingType) main/off/ranged без combat log, fallback UnitAttackSpeed/UnitRangedDamage. C_Spell.IsAutoRepeatSpell/IsCurrentSpell предотвращают повторное включение работающего Auto Shot. Класс также проверяет дальнобойное оружие и ammo. LazyG пока имеет XML Auto Shot без AutoShotActive.

## 13. Бафы, прокающие эффекты и стаки
Core/Atoms/Auras.lua ~9–28,~430–610; Spells.lua ~808–828. SPELL_ACTIVATION_OVERLAY_GLOW_SHOW/HIDE, C_SpellActivationOverlay.IsSpellOverlayed; estimated stacks по feeds/spends/consumers, fixed/rolling expiry, buff consumable сбрасывается после каста, auto-attack исключение. Для LazyG требуется единая AuraEstimate с происхождением/TTL и per-class consume rules, а не только Hunter.

## 14. Таланты именно Forever
Core/Atoms/Talents.lua ~1–660; TalentRangeData.lua. Forever использует C_Traits и C_ClassTalents.GetActiveConfigID, tree/node/entry/definition и три секции дерева, не 3.3.5 Classic talent API. Позиция таланта сопоставляется независимо от локализации, committed и staged ranks отличаются; invalidate при изменении spec, spellbook, talent config. Для LazyG нужны отдельные Forever Lua adapters и XML профили.

## 15. Action bars, macro, bindings
Core/Atoms/ActionSlots.lua ~1–81, UI/ActionBars.lua. C_ActionBar.HasAction/GetActionInfo, GetMacroSpell/GetMacroItem, C_ActionBar.FindSpellActionButtons, GetBindingKey, shapeshift bar. Механизм Sonah используется для подсветки; GetMacroSpell не гарантирует безопасное автоматическое выполнение условного макроса. В LazyG auto bindings пока исключают macro actions.

## 16. Предметы, тринкеты, ammo, totems и enchants
Core/Atoms/Items.lua ~1–345, TrinketData.lua, Casts.lua ~230–275, Auras.lua ~780–865. C_Item.GetItemSpell/GetItemCooldown/IsUsableItem/GetItemCount, независимая use история, damage/PvP trinkets, ranged ammo. PLAYER_TOTEM_UPDATE + безопасный GetTotemInfo корректируют историю шаманских тотемов. Weapon enchants из C_Item/C_PaperDollInfo. Требуют отдельных typed facts в manifest для других классов.

## 17. Движок, частота обновления и правила
Core/Organisms/Engine.lua ~184–490,~624–1100; Molecules/Conditions.lua ~1–1275. Приоритеты класса, precombat/aoe/healing/defensives/cooldowns, all/any/no/atLeast, provider sonah/blizzard/hybrid, C_AssistedCombat.GetNextCastSpell, stickySpell 0.3 секунды, HoldChannel, no auto-repeat, strictRange, event-driven Poke без storm на SPELL_UPDATE_COOLDOWN. Sonah является подсказчиком, а не драйвером клавиатуры. В LazyG XML и Logitech executor обязаны оставаться раздельными.

## 18. Диагностика и план
Core/Organisms/SelfTest.lua, Stats.lua: capability/secret tests, range bounds, uptime/rotation, раздельные события. Для LazyG — счётчики успешных WOW_CAST_EVENT, HID, Source of aura, estimated, target switch, stale, safe ZIP без приватных GUID/имён.

### Фактически внедрённый DEV-этап
Hunter Lua SENT+SUCCEEDED для Mark/Sting и target epoch; duration 120/15 s; Compact RGB v2 использует зарезервированный 1 byte отдельной маски event estimates **без увеличения RGB ячеек**; C# поддерживает v1 и v2, хранит hints отдельно от Auras; XML при Unknown может использовать WoW-событие, но известное отсутствие дебафа сильнее оценки. DebuffConfirmationGate снимает блокировку с меткой Estimated, а не Confirmed. Не используется Logitech IOCTL для fake cast. Фиксированный GCD не добавлялся. Игра ещё не проверена.

### Очередность
P0: live event→RGB→XML тест; InRange для ability и запрет HID вне диапазона; устранение глобального ожидания дебафов без завершения. P1: общий SecretSafe, runtime sharedCd, target identity, AuraRegistry и AutoShotActive. P2: талантные изменения, proc/charges, healer/group, предметы/тотемы. P3: полный условия/очередь/27 специализаций.
