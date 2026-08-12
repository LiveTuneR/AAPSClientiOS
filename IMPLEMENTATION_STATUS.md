# Статус интеграции AAPS 4 и Apple Watch

## Реализовано

- Версионированный glucose snapshot с историей, единицами, порогами и stale-временем.
- Доставка iPhone -> Apple Watch через `updateApplicationContext`, live message с ACK,
  background `transferUserInfo` и complication transfer с ограничением частоты.
- Нативное watchOS 10 приложение и WidgetKit-компликации: inline, circular, corner,
  rectangular с трёхчасовым графиком.
- Локальный cache в App Group и принудительная перезагрузка timeline после нового payload.
- Опциональный календарь `AAPS Glucose`: один заменяемый 10-минутный event с текущим
  значением, трендом и дельтой.
- Диагностика доставки на iPhone: канал, состояние, sequence, timestamp, ACK latency,
  экспорт текстом и очистка.
- AAPS 4 Client Control: Kotlin discriminator `type`, HMAC envelope, TTL, ACK/progress,
  preferences, batch prepare, bolus prepare/commit/stop и dismiss alarm.
- Болюс выполняется только после preview от master и отдельного подтверждения; финальный
  статус берётся из подписанного progress-документа.
- GitHub Actions генерирует Xcode-проект, собирает iOS/watchOS и запускает unit-тесты.

## Проверка на устройстве

1. Установить iOS и watchOS targets с одним Apple Team и включёнными App Groups/Keychain Groups.
2. Подключить Nightscout, дождаться нового значения и проверить экран диагностики доставки.
3. Проверить live ACK при открытом приложении часов, затем context/background при закрытом.
4. Добавить rectangular complication и проверить значение, график и переход в stale.
5. При необходимости включить календарный fallback и дать полный доступ к календарю.
6. Client Control проверять поэтапно: pairing/ping, preview, отказ/expiry, затем только
   контролируемая тестовая доставка и stop с наблюдением master и помпы.

## Не подтверждено или не реализовано

- Нет полевого теста на реальных iPhone/Apple Watch, Nightscout и AndroidAPS 4 master.
- Нет APNs backend: без внешнего сервера iOS не гарантирует минутный сетевой опрос в фоне.
  Реализованные WatchConnectivity и календарный каналы передают данные после пробуждения
  iOS-приложения, но системные бюджеты WidgetKit/watchOS остаются под контролем Apple.
- GlucoDataHandler является Android/Wear OS решением; его inter-app/complication API нельзя
  напрямую использовать на iOS/watchOS.
- Подписанный архив/TestFlight не создавался: нужны Apple Developer Team, provisioning profiles
  и зарегистрированные bundle/App Group identifiers.
- Команды терапии совместимы с изученным протоколом AAPS 4, но до полевого теста их нельзя
  считать клинически проверенными.
