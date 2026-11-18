LazyG 0.1.14-dev — экспериментальный транспорт RGB v3 (без включения в игровой мост)

Версия v2 0.1.13-dev: пользователь подтвердил быстрое обновление игровых состояний.
В 0.1.14-dev добавлены отдельно:
- Lua RgbV3Encoder.lua (не включен в действующий TOC и встроенный аддон).
- C# RgbV3Codec.cs (не подключён к действующему WowRgbBridge и Overview).
- Отдельные регрессионные тесты Lua/C# и проверка C# через GitHub Actions.
- Wire-формат повторяет архитектурную схему Sertyrew: 23 базовые ячейки, профильные дополнительные ячейки, CRC16/CCITT-FALSE, direct8 и stepped4.
- Новая точная спецификация: RGB_PROTOCOL_V3_SPEC_DRAFT.md.

ВАЖНО: это не готовый игровой RGB v3, не новая ротация и не проверенная в WoW версия v3.
Существующий экранный RGB v2 и Lua-аддон не изменены. Переустановка аддона не требуется.
При тесте EXE старый протокол v2 должен работать, как раньше.

Проверка:
1. Убедиться, что GitHub Actions завершён успешно и запущены тесты RGB v3 codec.
2. Запустить LazyG.exe, не переустанавливая действующий аддон v2.
3. Проверить те же четыре состояния цели/боя и скорость Overview; это регрессионный тест v2.
4. Не ожидать отображения HP/ресурса по протоколу v3 — визуальный мост v3 ещё не подключён.

Команда PowerShell из корня репозитория:
dotnet publish LazyG/Windows/LazyG.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=None

Ручной тест кодера/декодера (требуются .NET 8 SDK и, отдельно, Lua 5.x):
dotnet run --project LazyG/Tests/RgbV3CodecTests.csproj -c Release
lua LazyG/Tests/rgb_v3_encoder_test.lua
