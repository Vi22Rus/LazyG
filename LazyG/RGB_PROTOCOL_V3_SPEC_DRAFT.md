# LazyG RGB v3 — спецификация кодера/декодера по модели Sertyrew

**18 ноября 2026.** Заменяет предыдущий TLV-черновик этого файла. Статус: **реализован изолированный кодер Lua и декодер C#, НЕ интегрировано с реальным WoW**, игровые возможности и профили продолжают использовать проверенный RGB v2. Это собственная реализация **wire-модели Sertyrew**, а не копирование исходников либо доказанная двоичная совместимость с закрытым WarMate.exe.

**Код:** `LazyG/AddonTemplate/RgbV3Encoder.lua`, `LazyG/Windows/RgbV3Codec.cs`. **Автоматические тесты:** `LazyG/Tests/Program.cs`, `LazyG/Tests/RgbV3CodecTests.csproj`; CI `.github/workflows/build-windows.yml`. Прочее: [RGB_PROTOCOL_V3_PLAN.md](RGB_PROTOCOL_V3_PLAN.md).

## 1. Проверенный референс и принцип реализации

Просмотрены реальные модули `Sertyrew/Protocol/Protocol.lua`, `Encode.lua`, `Crc16.lua`, `Bits.lua`, `Core/Layout.lua`, `Output/Strip.lua`, `Output/FrameAnchor.lua` из приложенного архива. У референса: версия протокола **1**, `plainCells=5`, `coreCells=23`, `cellPixels=3`, `maxCellsPerRow=96`; базовые ячейки формируются по явной схеме имён/полей, расширения — по профилю, затем добавляется одна завершающая checksum-ячейка. `direct8` — 8-битные RGB; `stepped4` — 4-битный RGB, канал кратен 17. Контроль — CRC16/CCITT-FALSE poly `0x1021`, init `0xFFFF`, стандартный check `0x29B1`.

**Важное различие:** `RGB v3` — имя следующего этапа **LazyG**. В формате wire-пакета для соответствия Sertyrew в `Header.R` установлено **1**, а не **3**. Сторонний декодер WarMate.exe не анализировался до уровня подтверждения всех внутренних требований.

## 2. Логическая структура (индексы с нуля)

| Индексы | Ячейки | R | G | B |
|---|---|---|---|---|
| 0 | MarkerA | 255 | 0 | 255 |
| 1 | MarkerB | 0 | 255 | 0 |
| 2 | RefWhite | 255 | 255 | 255 |
| 3 | RefBlack | 0 | 0 | 0 |
| 4 | Header | wire protocol version = 1 | frame counter u8 | encoding (bits 0–1), profile_active (bit 2), прочие статусные биты по схеме |
| 5 | Identity | profile hash high | profile hash low | class id (4 бита), talent tree (2), talent group (1), untalented (1) |
| 6 | AddonInfo | addon_major | addon_minor | profile_index |
| 7 | StateFlags | 8 флагов игрока | 8 флагов движения/каста/питомца | 8 флагов цели |
| 8 | Vitals | HP игрока | HP цели | combo points |
| 9 | Power | power type | power high | power low |
| 10 | PowerMax | max power high | max power low | HP питомца |
| 11 | Gcd | remaining | duration | latency |
| 12 | CastRemain | remaining high | remaining low | ability index |
| 13 | CastTotal | duration high | duration low | cast kind |
| 14 | Accepted | ability | sequence | button |
| 15 | Rejected | ability | sequence | code |
| 16 | Focus | health | flags | cast remaining |
| 17 | TargetCast | remaining high | remaining low | target-of-target |
| 18 | Threat | enemy count | confidence | situation |
| 19 | ClassA | form | counter | swing remaining |
| 20 | ClassB | enchant/lust flags | main enchant remaining | offhand enchant remaining |
| 21 | TargetInfo | level | class/boss/TTD flags | TTD |
| 22 | FocusUnit | unit | threat percent | instance/target flags |
| 23.. | Profile extras | Тройки каналов в строго согласованном порядке профиля |
| last | Checksum | CRC16 high | CRC16 low | 0-based index checksum cell mod 256 |

**Общая длина:** `23 + extensionCells + 1` логическая ячейка. При отсутствии extras **24 логические ячейки**; это важное отличие от неточного утверждения «23 вместе с checksum». В `direct8` 24 физические ячейки. В `stepped4` первые 5 остаются обычными, каждая из остальных раскладывается в две физические: `5+2*(24−5)=43`. При 2 extra — 26/47 соответственно.

**Частотные и физические параметры** `3 физ. пикселя`, `96 ячеек/строка` — именно свойства референса. Рендер, калибровка и несколько строк в текущем LazyG **ещё не реализованы**.

## 3. Кодирование

- `direct8`: записать исходные байты RGB логических ячеек без преобразования.
- `stepped4`: первые 5 ячеек (15 байтов) без изменений, для **каждого следующего исходного байта** `b` записать два физических канала `floor(b/16)*17` и `(b%16)*17`. Три последовательных канала составляют физическую RGB-ячейку.
- Декодер проверяет кратность 17 и собирает байт как `(first/17)*16 + second/17`. Нельзя просто считать весь массив физическими пикселями «без преобразования» при stepped4.
- Раскладка блоков/способностей/аур **позиционная и определяется профилем** (Sertyrew `Core/Layout.lua`), не TLV. В этой итерации все дополнительные ячейки принимаются/возвращаются как позиционные RGB-тройки, а их игровая семантика будет задаваться отдельным совместимым manifest. Декодер требует **ожидаемую длину extras**; иначе отказывает.
- `Header.B & 3`: 0 direct8, 1 stepped4; остальные значения reject. `Header.R !=1` reject.
- Профильный hash — `Identity.R*256+Identity.G`; опциональная проверка ожидаемого хэша в C# перед использованием.
- Максимум 512 дополнительных логических ячеек — ограничение безопасности **LazyG** текущего изолированного декодера, а не значение референса.

## 4. CRC и завершающая ячейка

CRC-16/CCITT-FALSE: poly 0x1021, init 0xFFFF, refin=false, refout=false, xorout=0; ASCII `123456789` => **0x29B1**. Расчёт по исходным **логическим RGB-байтам** от **ячейки 4** до последней ячейки данных включительно; 4 стартовые ячейки и финальная checksum-ячейка исключены.

Для `N = 23 + extensionCells`: checksum-ячейка (индекс `N`) содержит `(crc >> 8, crc & 255, N % 256)`. Декодер проверяет маркеры, версию/режим, физическую длину из профиля, checksum cell index, CRC и profile hash.

**CRC ловит искажения, но не удостоверяет авторство и не гарантирует атомарность при частично нарисованном кадре**. Обработка свежести и счетчика кадров — следующий уровень будущего GameState.

## 5. Исходные векторы (независимый расчёт Python `binascii.crc_hqx(data,0xffff)`)

Общий тестовый Core: маркеры [FF 00 FF], [00 FF 00], [FF FF FF], [00 00 00]; Header [01 07 04]; Identity [BE EF 13]; AddonInfo [01 01 02]; StateFlags [01 01 03]; Vitals [4D 36 00]; Power [00 00 58]; PowerMax [00 64 00]; остальные ячейки Core до 22 включительно нулевые.

- **Вектор A:** без extras, checksum index **23**, CRC **0x8B22**, footer `8B 22 17`, **24** direct8-ячейки.
- **Вектор B:** те же Core, 2 extras `0A 14 1E`, `FF 00 0F`; checksum index **25**, CRC **0xD79A**, footer `D7 9A 19`, **26** direct8-ячеек.
- **Вектор C:** как A, но encoding ID=1 в Header.B, с пересчитанным CRC; **43** физические stepped4-ячейки.

Негативные тесты: изменение цвета без CRC, неверная копия индекса, несовместимый профиль, неверное количество ячеек, ошибка версии, повреждение канала stepped4. В тестах также проверяется число 0x29B1 для общепринятого CRC input.

## 6. Область реализации и ограничения

**Сделано в коде:** изолированный Lua-модуль BuildCore/Encode/Crc16 с 23 базовыми ячейками и профильно задаваемыми extras; отдельный C# TryDecode с проверками, CRC, direct8/stepped4 и доступом к распакованным базовым ячейкам; тестовый CLI C# с векторами и повреждениями. Модуль Lua не изменяет текущий установленный аддон и не запускается через его TOC; декодер не подключён к текущему RGB захвату/UI.

**В 0.1.15-dev реализовано дополнительно (USER-UNTESTED):** отдельная полоска Forever RGB v3 с 24 ячейками direct8 под v2 на y=-12 UI; в новый устанавливаемый аддон включены RgbV3Encoder.lua и RgbV3Panel.lua как EmbeddedResource; в Windows есть поиск/декодирование v3 при едином захвате с v2 и вывод CRC/HP/ресурса. Хеш тестового профиля 0x4C47, extras=0. 255 в HP = unknown, у Power type 255 = unknown; нельзя использовать эти числа как достоверное игровое состояние. **Не сделано:** полный реестр профилей и семантика всех полей, полноценная калибровка UI Scale, автоматическое обнаружение разных профилей, combat state с Known/Unknown, XML-ротации и пользовательская проверка v3. Не объявлять эту dev-итерацию готовой к игровой проверке v3.

**Ключевое правило доступности:** из-за WoW secret/protected API отсутствие значения не должно становиться доказанным false/zero в логике будущих XML-условий. `BuildCore` использует нули для пустых тестовых полей, но **они не содержат статус Known/Unknown**; такие пакеты запрещено напрямую использовать для реальной боевой логики до внедрения capabilities/snapshot модели.

**Следующий этап:** проверка Lua-векторов и C# в CI, затем согласованный профиль Forever, физический вывод/чтение v3 с возможностью одновременного fallback к v2 и отдельный игровой тест.
