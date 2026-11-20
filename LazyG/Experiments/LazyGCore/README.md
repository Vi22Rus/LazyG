# LazyGCore native RGB v2 + Windows auto-bindings — 2026-11-20 (DEV)

The experimental Windows app reads **only** LazyGCore's eight RGB cells. Legacy RGB is never read. The new native v2 frame also carries the recommended direct spell action-bar key (HID modifier and usage) and explicit readiness evidence. The app can send a key through Logitech G HUB only if all native gates are confirmed, the sequence is fresh, the game is foreground, the device is connected, and minimum pacing is met. On unknown/protected inputs it blocks, logs why, and makes **no guess**. It does not consider G HUB IO proof of a successful WoW cast.

In Windows choose Hunter BM PvE → Start LazyGCore (DEV), with Logitech G HUB running. In Support choose Record CORE / XML comparison and Export diagnostic ZIP. The XML shadow remains UNKNOWN until the native protocol exposes independent game state; it is not yet a meaningful full-rotation comparison. Game behavior remains unverified. Current native v2 only authorizes hostile target actions; self-buffs fail closed.

Install this addon with the single directory Interface/AddOns/LazyGCore containing LazyGCore.toc. Use the updated Windows binary from the matching experimental Actions run, not the older v1-only decoder. Keep the main branch unchanged.

Legal caution: the upstream license retained in the source tree restricts modification and redistribution without permission; do not treat the development fork as authorized for public redistribution.

---

# LazyGCore — полноценный экспериментальный Lua-форк

Статус: **0.1.0-dev / GAME-UNTESTED**. Отдельная ветка, main не затронута.

Полное игровое ядро из пользовательского исходного архива версии 1.2.6. Разрешено модифицировать и распространять под другим названием согласно приложенной лицензии. Runtime-брендинг, глобальные имена, интерфейс и пути названы **LazyGCore**, оригинальная лицензия остаётся отдельно в юридической документации.

Это НЕ внешний аддон-мостик. Встроенная RGB-передача вызывается непосредственно из Publish в Core/Organisms/Engine.lua, после формирования рекомендации. Отдельный модуль Core/Atoms/RgbWire.lua только рисует кодированную полосу.

Формат: 8 RGB ячеек, magic LGC, версия 1, номер кадра, состояние рекомендации, SpellID 24 bit, флаги outOfRange/waiting/noPower с битами качества, CRC16-CCITT; x=0, y=-54. Прямые защищённые значения не сериализуются. Передаётся готовая рекомендация, а не все исходные секретные игровые факты.

**Историческая заметка (v1):** на первом этапе Windows EXE ещё не декодировал этот формат. Сейчас экспериментальная Windows-сборка поддерживает v2 и Logitech с проверками, описанными выше. GCD внутри игрового ядра сейчас оставлен исходным; качество GCD в RGB=UNKNOWN. Его алгоритм ещё надо сравнить с 29515 в текущем LazyG и подтвердить на настоящем Forever. Исполнять непроверенные рекомендации автоматически запрещено.

Архив источника проверяется по SHA256:
4bc89bf98c95c8559845b8e4abb009db0740285f514d7e9c0e15d2e7cb63341c.
Для полного воспроизводимого форка в Actions требуется ровно этот ZIP. Если CDN возвращает другой архив, генерация должна остановиться. Ветка содержит скрипт генерации и запуск отдельной CI.

Команда PowerShell для Windows single-EXE (тот же текущий Windows-движок):

    dotnet publish .\LazyG\Avalonia\LazyG.Avalonia.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o .\publish
