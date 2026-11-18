LazyG 0.1.17-dev — экспериментальные HP/ресурс через Blizzard UI Curve

Статус DEV/USER-UNTESTED. По предыдущему тесту 0.1.16-dev обычный UnitHealth / UnitPower вызывал protected/API error. В 0.1.17-dev добавлен совершенно отдельный способ проверки через UnitHealthPercent / UnitPowerPercent, C_CurveUtil и Texture:SetAlpha. Модель основана на механизмах из Sonah Forever и NAG Camelot, код собственный.

Что новое:
- Третья полоска на y=-24 UI под двумя прежними полосками.
- Первые 2 ячейки cyan/magenta для обнаружения.
- Три группы: HP игрока, HP цели, основной ресурс.
- В каждой группе 1 статусная ячейка (зелёная=кривая применена, красная=нет) и 9 порогов 10–90%.
- Windows показывает «curve probes: HP 50–59% · target HP 70–79% · resource 20–29%» или «unavailable». Это пример.
- Пороговый диапазон не является точным HP, не идёт в XML или автоматические нажатия. Возможность передачи секретного UI-результата в пиксели ещё требует проверки.
- Старый RGB v2 и CRC-полоска RGB v3 остаются без изменений.

Тест:
1. Скачать один EXE в Artifacts → LazyG-Windows-x64 из указанного успешного запуска GitHub Actions.
2. В Setup установить аддон с новым именем (предыдущий LazyG аддон выключить), сделать /reload.
3. Проверить v2 и RGB v3 CRC PASS.
4. В Overview найти «curve probes: HP ... · target HP ... · resource ...».
5. При известном здоровье по UI проверить, меняется ли порог после урона, на живой цели и без цели.
6. Сообщить точные результаты; если «UI curve thresholds unavailable», тоже сообщить.
7. Не менять графические настройки специально. Не заявлять об успешной поддержке API без игрового теста.

Команда PowerShell для одного EXE:
dotnet publish LazyG/Windows/LazyG.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=None
