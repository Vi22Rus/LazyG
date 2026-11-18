LazyG 0.1.16-dev — диагностика причины Unknown в RGB v3 Forever

0.1.15-dev пользователь проверил в WoW: RGB v2 правильно показывает Hunter Tauren Level 30 Beast Mastery и состояния цели; RGB v3 CRC PASS, frame=196; все HP и Resource показывают unknown.
RGB транспорт v3 проходит проверку, но причина недоступности численных полей не установлена.

Изменения этой dev-версии:
- В дополнительной диагностической ячейке v3 (logical cell 22) Lua передаёт три статуса: HP игрока, HP цели, ресурс.
- Коды: 0=OK, 1=API missing, 2=non-numeric, 3=protected/API error, 4=invalid maximum, 5=no target.
- Windows Overview выводит причину рядом с каждым значением.
- Полоски v2/v3, CRC16, маркеры и 150ms Windows опрос НЕ изменены.
- Новая установленная папка аддона (TOC 0.1.16-dev) нужна для проверки; старый аддон необходимо отключить, чтобы не наложились полоски.

Проверка:
1. Скачать LazyG.exe из SUCCESS GitHub Actions для 0.1.16-dev.
2. В Setup установить аддон под новым уникальным именем. Выключить прежние тестовые LazyG в меню AddOns WoW.
3. /reload; проверить, что RGB v2 остаётся рабочим и v3 CRC PASS.
4. Сообщить в точности три строки/значения: HP (...), target HP (...), resource (...) и соответствующие коды.
5. Сначала на существующей живой цели, затем без цели; это позволит отличить статус 5 от запрета API.
6. Не сбрасывать графические настройки. Не считать ошибку получения чисел доказательством неисправности RGB.

Текущий статус: только диагностика API; XML-ротаций и нажатий нет. 0.1.13-dev — проверенная точка отката.

Команда PowerShell из корня репозитория для единого EXE:
dotnet publish LazyG/Windows/LazyG.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=None
