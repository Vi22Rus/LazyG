LazyG 0.1.19-dev — исправление RGB Curve 5% (Forever)

Что показал тест 0.1.18-dev:
- Третья RGB-полоска с зелёными статусами и фиолетовым маркером видна.
- В Overview: UI Curve Thresholds unavailable.

Найдены и исправлены ошибки в Windows:
- Для второй/третьей группы исправлено смещение g*10 -> g*20 (теперь 20 cells на группу).
- Диапазоны рассчитываются с шагом 5%, а не 10%.
- Захват экрана расширен с 350 до 800px для учёта UI Scale.
- Добавлен автоматический тест трёх групп при pitch 6px и значениях 95–100%, 50–54%, 20–24%.
- RGB v2 и RGB v3 CRC не менялись.

Как проверить:
1. Скачай LazyG-Windows-x64 в Artifacts после успешного GitHub Actions.
2. Установи через Setup аддон под новым именем; отключи предыдущий тестовый LazyG-аддон и /reload.
3. В Overview проверь RGB v2 и RGB v3 CRC PASS.
4. Curve probes должны показывать HP/target HP/resource с диапазонами по 5%.
5. При 100% ожидается 95–100%; затем опусти HP цели до ~50%, ~20% и сравни с Blizzard UI.
6. Если снова unavailable, пришли строку RGB Connection и сообщи UI Scale/режим окна, не сбрасывая настройки игры.

0.1.19-dev остаётся тестовой dev-версией до проверки в WoW. 0.1.17-dev — подтверждённая точка отката 10% Curve.

PowerShell из корня репозитория:
dotnet publish LazyG/Windows/LazyG.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -p:DebugType=None
