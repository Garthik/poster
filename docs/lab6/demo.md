# Практическая защита Sprint 6

Все команды ниже выполняются в **WSL2 Ubuntu**, из `/mnt/c/TomeD/VSCode/Proga/Afisha/poster`. Сначала покажите `docs/lab6/README.md`. Полный автоматизированный путь занимает запуск образов и несколько минут тестов; первый запуск требует сети для Node.js/драйвера. Результаты берутся из `artifacts/lab6`, а не из ожидаемых чисел в этой инструкции.

## 0. Подготовить демонстрацию и сохранить прошлые лабораторные

**Что реализовано:** отдельные Compose-проект и volumes Lab6; повторно используется `mongo/schema.js`. PostgreSQL и standalone Lab5 не конвертируются в rs0 и не удаляются.

**Открыть:** `docker-compose.lab5.yml`, `docker-compose.lab6.yml`, `mongo/schema.js`, `docs/lab6/architecture.md`.

```bash
cd /mnt/c/TomeD/VSCode/Proga/Afisha/poster
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
bash scripts/lab6.sh init
bash scripts/lab6.sh all
```

**Ожидание:** `all` заканчивается `PASS: semantic artifact verification...`; код возврата `echo $?` равен 0. `all` не выполняет остановку PRIMARY. Standalone Lab5 по-прежнему отдельный сервис на 27018.

**Критерий:** предыдущие файлы схем/SQL/Compose не изменены; артефакты Lab6 созданы отдельно. Пароли преподавателю не показывать. `init` сообщает только путь; повторный init сохраняет существующие файлы. Replica Set обеспечивает отказоустойчивость редакционного контента, PostgreSQL по-прежнему отвечает за билеты и деньги.

## 1. Показать три голосующих узла и авторизацию

**Открыть:** `mongo/lab6/start-mongo.sh`, `bootstrap.js`, `scripts/lab6/init.sh`, `artifacts/lab6/replica-status.json`.

```bash
bash scripts/lab6.sh status
# Выбрать сервис, у которого в выводе PRIMARY:
bash scripts/lab6.sh shell mongo1
```

Далее в mongosh (после failover замените mongo1 актуальным PRIMARY из status):

```javascript
db.hello()
db.getSiblingDB('admin').runCommand({replSetGetStatus:1}).members.map(
  m => ({name:m.name,state:m.stateStr,health:m.health}))
db.getSiblingDB('admin').runCommand({replSetGetConfig:1}).config.members.map(
  m => ({host:m.host,votes:m.votes,priority:m.priority,arbiterOnly:m.arbiterOnly}))
db.getCollectionInfos({name:'visitor_feedback'})[0].options
```

**Ожидание:** setName `rs0`; ровно один PRIMARY и два SECONDARY, health=1; каждый votes=1, priority>0, arbiter отсутствует. Валидатор — `$jsonSchema`, strict/error. `shell` аутентифицируется из secret-файлов, пароль не передаётся в argv.

**Критерий:** `status` возвращает 0 только при полной проверке состояний и голосов, а не просто работающих контейнерах. Три полных узла позволяют пережить один отказ с большинством 2/3. В Docker имена разрешает Compose DNS; для прямого клиента WSL нужны одинаковые hostname/port и `/etc/hosts`, см. README. Keyfile обеспечивает внутреннюю аутентификацию, а users/roles — клиентскую.

## 2. Показать детерминированные данные и реальные поля

**Открыть:** `mongo/lab6/data.mjs`, `seed.mjs`, `artifacts/lab6/seed.json`, `artifacts/lab5/pg_events.json`.

```bash
bash scripts/lab6.sh seed
cat artifacts/lab6/seed.json
# После повторного seed повторно снять измерения, чтобы обновить связанный отчёт:
bash scripts/lab6.sh benchmark
```

В mongosh текущего PRIMARY:

```javascript
db.event_pages.countDocuments({_id:/^lab6-seed-page-/})
db.visitor_feedback.countDocuments({_id:/^lab6-seed-feedback-/})
db.event_pages.findOne({_id:'lab6-seed-page-000007'})
db.visitor_feedback.findOne({pageSlug:'lab6-seed-page-000007',moderation:'approved'})
```

**Ожидание:** по умолчанию 12000 страниц и 60000 отзывов; `createdAt` — BSON date, `rating` и `schemaVersion` — integer; `editor.alias` действительно входит в модель. Seed `20261104`, SHA256 при одинаковых параметрах повторяется. `pgEventId` берётся из имеющегося экспорта PostgreSQL, а не выдумывается.

**Критерий:** нет роста числа документов при повторном seed. Удаляются только зарезервированные seed-ID Lab6, не Lab5/рабочие страницы. Устойчивый псевдослучайный генератор и фиксированные даты дают одинаковые условия для измерений.

## 3. Первый запрос: последние одобренные отзывы

**Открыть:** `mongo/lab6/benchmark.mjs` (первый элемент QUERIES), `artifacts/lab6/plans/feedback-before-1.json`, `feedback-after-1.json`.

```bash
bash scripts/lab6.sh benchmark
python3 -m json.tool artifacts/lab6/plans/feedback-before-1.json | less
python3 -m json.tool artifacts/lab6/plans/feedback-after-1.json | less
cat artifacts/lab6/benchmark/medians.csv
```

В mongosh текущего PRIMARY:

```javascript
db.visitor_feedback.getIndexes()
db.visitor_feedback.find({pageSlug:'lab6-seed-page-000007',moderation:'approved'})
  .sort({createdAt:-1,_id:1}).limit(100).explain('executionStats')
```

**Ожидание:** до оптимизации исходный индекс Lab5 может дать IXSCAN/FETCH с блокирующим SORT. После — новый `lab6_feedback_page_moderation_created_id` и IXSCAN/FETCH без SORT. Точные стадии смотреть в сохранённом winning plan; rejected plans не являются выбранным планом.

**Критерий:** explain после использует новый индекс без принудительного hint; `nReturned=100` в обеих фазах; набор и порядок ID совпали. `totalDocsExamined` уменьшается. Время может остаться 0–1 ms и само по себе не доказывает отсутствие эффекта. Составной индекс сначала сужает по двум равенствам, затем уже выдаёт нужный порядок по времени и `_id`.

## 4. Второй запрос: публикации выбранного редактора

**Открыть:** второй элемент QUERIES, `plans/pages-before-1.json`, `plans/pages-after-1.json`, `benchmark/summary.md`.

```bash
cat artifacts/lab6/benchmark/summary.md
python3 -m json.tool artifacts/lab6/plans/pages-before-1.json | less
python3 -m json.tool artifacts/lab6/plans/pages-after-1.json | less
```

В mongosh:

```javascript
db.event_pages.find({status:'published','editor.alias':'editor-07'})
  .sort({headline:1,_id:1}).limit(100).explain('executionStats')
db.event_pages.getIndexes().map(i=>({name:i.name,key:i.key}))
```

**Ожидание:** исходный индекс `{status,keywords}` не удовлетворяет редактору и headline; до оптимизатор может выбрать COLLSCAN+SORT. После используется `lab6_pages_status_editor_headline_id` с ключом `{status:1,'editor.alias':1,headline:1,_id:1}`. FETCH нужен, потому что возвращаем полные документы.

**Критерий:** прежние `_id_`, `pgEventId_1`, `status_1_keywords_1` сохранены; after действительно использует новый индекс. Селективный бизнес-фильтр требует меньше прочитанных документов; наличие уже одного индекса не означает оптимизацию любой сортировки.

## 5. Серии измерений, планы и медианы

**Открыть:** `benchmark/measurements.csv`, `medians.csv`, `results.json`, `mongo/lab6/check.mjs`, `tests/lab6/metrics.test.mjs`.

```bash
cat artifacts/lab6/benchmark/measurements.csv
cat artifacts/lab6/benchmark/medians.csv
bash scripts/lab6.sh check
bash scripts/lab6.sh test
```

В mongosh:

```javascript
const e = db.visitor_feedback.find({pageSlug:'lab6-seed-page-000007',moderation:'approved'})
  .sort({createdAt:-1,_id:1}).limit(100).explain('executionStats');
({time:e.executionStats.executionTimeMillis,docs:e.executionStats.totalDocsExamined,
  keys:e.executionStats.totalKeysExamined,returned:e.executionStats.nReturned})
```

**Ожидание:** ≥20 JSON-планов, 20 строк измерений при 5 повторах, четыре строки медиан. Три прогрева перед каждой фазой; измеряются серверное и wall-clock время. Пример ручной проверки медианы в WSL:

```bash
python3 - <<'PY'
import csv, statistics
with open('artifacts/lab6/benchmark/measurements.csv') as f:
    rows = list(csv.DictReader(f))
for query in ('feedback', 'pages'):
    for phase in ('before', 'after'):
        xs = [float(r['executionTimeMillis']) for r in rows if r['query']==query and r['phase']==phase]
        print(query, phase, len(xs), statistics.median(xs))
PY
```

**Критерий:** `check` сравнивает каждую метрику CSV с полным explain и пересчитывает медианы. Он проверяет результат и живую БД, не только наличие файлов. Кеш, дискретность времени, параллельная нагрузка и выбор оптимизатора объясняют неоднозначные временные результаты; ускорение по времени не гарантируется.

## 6. Bulk API и частичный успех

**Открыть:** `mongo/lab6/bulk.mjs`, официальный импорт `MongoBulkWriteError`, `artifacts/lab6/bulk.json`.

```bash
bash scripts/lab6.sh bulk
cat artifacts/lab6/bulk.json
bash scripts/lab6.sh bulk
```

В mongosh после завершения:

```javascript
db.visitor_feedback.countDocuments({_id:/^lab6-bulk-/}) // 0: временные данные убраны
db.getCollectionInfos({name:'visitor_feedback'})[0].options.validator.$jsonSchema.properties.rating
```

**Ожидание:** один `collection.bulkWrite(operations,{ordered:false})`, 500 insertOne, 500 updateOne, ошибочный rating=9 (121), дублирующий `_id` (11000). Оба кода проверены. Итог — 500 вставок, 500 изменений, 1000 успешных из 1002 операций. Отдельный replay стабильных IDs через upsert даёт matched=1000, modified=0, upserted=0 без очистки между исходным пакетом и replay.

**Критерий:** ожидаемое исключение обработано по `error.result` и `writeErrors`; нет необъяснённых write concern errors. Валидные операции после ошибочных выполнены, данные проверены запросами, затем убраны в finally. `ordered:false` допустим, потому что изменения относятся к разным документам и не зависят от порядка. Это Bulk API драйвера, не цикл отдельных insertOne.

## 7. Транзакция: COMMIT сразу в двух коллекциях

**Открыть:** `mongo/lab6/transactions.mjs`, функция `publish()`, `transaction-retry.mjs`, `artifacts/lab6/transactions.json`.

```bash
bash scripts/lab6.sh transaction
cat artifacts/lab6/transactions.json
```

В mongosh:

```javascript
db.event_pages.findOne({_id:'lab6-seed-page-000007'},{status:1})
db.editorial_collections.findOne({_id:'lab6-seed-collection'},{pageSlugs:1})
db.lab6_publication_operations.getIndexes()
db.lab6_publication_operations.countDocuments({_id:/^lab6-tx-/}) // 0 после уборки
```

**Ожидание:** в отчёте commit.alreadyApplied=false, replay.alreadyApplied=true. Программа внутри теста проверила published, ровно одну ссылку и ровно один receipt. Служебная коллекция имеет unique `_id`. После теста временные бизнес-документы и receipt удалены; поэтому демонстрировать их сохранённое состояние через find после теста не нужно — покажите запросы assert в коде и реальный отчёт.

**Критерий:** session передаётся в каждую операцию трёх коллекций, COMMIT атомарен, стабильный operationId включён в ту же транзакцию. PostgreSQL не участвует; распределённой транзакции с продажей билета не заявляется.

## 8. ROLLBACK после первой записи и изоляция

**Открыть:** `afterFirstWrite` в `transactions.mjs`, `results.rollback` отчёта.

```bash
bash scripts/lab6.sh transaction
```

В mongosh (без изменения бизнес-документов можно показать snapshot-чтение):

```javascript
const s = db.getMongo().startSession();
s.startTransaction({readConcern:{level:'snapshot'},writeConcern:{w:'majority'},readPreference:'primary'});
const d = s.getDatabase('ticket_platform_docs');
d.event_pages.findOne({_id:'lab6-seed-page-000007'});
d.editorial_collections.findOne({_id:'lab6-seed-collection'});
s.abortTransaction();
s.endSession();
```

**Ожидание в автоматическом тесте:** внутри транзакции первая страница уже published, другой клиент видит draft. Затем искусственная бизнес-ошибка вызывает abort. Полные снимки **обеих** коллекций равны исходным, receipt отсутствует.

**Критерий:** ошибка действительно возникает после update, а не до него. Изменения не видны внешнему клиенту до commit; исключение не оставляет частично опубликованную страницу.

## 9. Временные ошибки, безопасный retry и дубли

**Открыть:** `runTransaction()` и `CommitUncertainError`, failCommand в `transactions.mjs`, `tests/lab6/retry.test.mjs`.

```bash
bash scripts/lab6.sh transaction
bash scripts/lab6.sh test
cat artifacts/lab6/transactions.json
```

В mongosh текущего PRIMARY:

```javascript
db.getSiblingDB('admin').runCommand({getParameter:1,'failpoint.failCommand':1})
db.lab6_publication_operations.getIndexes() // unique _id для operationId
```

**Ожидание:** TTE — attempt=2; UnknownCommit — attempt=1, commitAttempts=2. В журнале retries различаются scope=transaction и scope=commit. После обычного теста failpoint выключен. В lostReply bodyCalls=1 при двух commit-попытках: первый commit действительно завершился, а его ответ был намеренно скрыт тестовым клиентом. Повтор операции с тем же ID не дублирует связь; другой payload с тем же ID отвергается.

**Критерий:** используются настоящие серверные error labels с фильтром appName; пост-коммитная потеря ответа отдельно обозначена как клиентская инъекция. Unit-тесты проверяют конечные лимиты: 4 тела/5 commit по умолчанию, необратимая ошибка не скрывается. Нельзя повторять тело по UnknownCommit: операция могла уже успешно завершиться. Если результат commit так и не выяснен, проверять receipt и повторять только прежний operationId.

## 10. Concerns и read preference в коде

**Открыть:** `mongo/lab6/lib.mjs`, `docs/lab6/concerns.md`.

```bash
sed -n '1,100p' mongo/lab6/lib.mjs
bash scripts/lab6.sh status
```

В mongosh:

```javascript
db.visitor_feedback.find({moderation:'approved'}).readConcern('majority').readPref('primary').limit(1)
db.hello()
```

**Ожидание:** client: majority/majority+j/primary; transaction: snapshot/majority+j/primary. `retryWrites=true`, конечные таймауты. Исключение — direct secondary-read возвращённого после failover узла, чтобы доказать catch-up.

**Критерий:** настройки есть в исполняемом MongoClient/transaction options. Majority уменьшает риск rollback подтверждённой записи, но не исключает timeouts/потерю большинства/дисков. Secondary может отставать; для редакционной витрины приемлем secondaryPreferred при осознанном допуске задержки, публикации требуют primary. Replica Set не заменяет backup.

## 11. Цена индекса для INSERT, UPDATE и хранения

**Открыть:** `mongo/lab6/index-write.mjs`, `artifacts/lab6/index-write/summary.md`, CSV и один `stats-after-1.json`.

```bash
bash scripts/lab6.sh index-write
cat artifacts/lab6/index-write/summary.md
cat artifacts/lab6/index-write/medians.csv
```

В mongosh:

```javascript
db.lab6_write_baseline.getIndexes()
db.lab6_write_indexed.getIndexes()
db.runCommand({collStats:'lab6_write_indexed',scale:1})
db.lab6_write_baseline.countDocuments({}) // 0 после cleanup
db.lab6_write_indexed.countDocuments({})  // 0 после cleanup
```

**Ожидание:** две baseline-структуры индексов против трёх с дополнительным Q1-индексом, одинаковый SHA256 данных. По пять вставок и обновлений с одним прогревом, порядок фаз чередуется. CSV: wall time, docs/s, logical data, storage и index bytes; сырые collStats сохранены **до** уборки, поэтому текущая пустая коллекция уже не отражает момент измерения.

**Критерий:** одинаковые документы, concerns и базовые индексы; update меняет createdAt, входящий в новый индекс. Медианы пересчитывает check. Не требуется искусственно получать замедление: кеш, checkpoint и выделение страниц влияют на конкретные значения. Индексы требуют поддержки структуры и места; storageSize не обязан уменьшаться после delete.

## 12. Остановить текущий PRIMARY и подтвердить восстановление

**Открыть:** `scripts/lab6/failover.sh`, `mongo/lab6/cluster.mjs`, `docs/lab6/failover-runbook.md`.

```bash
bash scripts/lab6.sh status
bash scripts/lab6.sh failover --yes
cat artifacts/lab6/failover.json
bash scripts/lab6.sh status
bash scripts/lab6.sh check --with-failover
```

В mongosh **нового PRIMARY**, выбрав его по status:

```javascript
db.hello().primary
db.getSiblingDB('admin').runCommand({replSetGetStatus:1}).members.map(m=>({host:m.name,state:m.stateStr,health:m.health}))
db.visitor_feedback.countDocuments({_id:/^lab6-failover-/}) // 0: cleanup
```

**Ожидание:** адреса before и after различаются, в JSON sameClient=true, beforeWriteSurvived=true, afterWriteRead=true, returnedState='SECONDARY', returnedNodeHasNewWrite=true. Лог показывает динамически выбранный сервис остановки. Тот же MongoClient, открытый до сбоя, выполняет операции после выборов по полной URI без пересоздания приложения.

**Критерий:** недостаточно просто увидеть работающие контейнеры; есть новая запись/чтение и доказательство catch-up старого PRIMARY. Скрипт автоматически возвращает узел даже при ошибке, насколько Docker доступен. Останавливается один узел; при потере 2/3 большинство недоступно и majority-записи не могут продолжаться. `recoveryMillis` — измеренный участок после завершения stop, не полная длительность простоя и не обещание SLA.

## 13. Финальные проверки, журналы и повторяемость

**Открыть:** `mongo/lab6/check.mjs`, `artifacts/lab6/checks.json`, `unit-tests.tap`, `logs/`.

```bash
bash scripts/lab6.sh test
bash scripts/lab6.sh check --with-failover
cat artifacts/lab6/checks.json
cat artifacts/lab6/unit-tests.tap
# Остановить только отдельный Lab6, сохранив данные:
bash scripts/lab6.sh down
# Повторно поднять те же тома и проверить:
bash scripts/lab6.sh up
bash scripts/lab6.sh check --with-failover
```

В mongosh после повторного up:

```javascript
db.event_pages.countDocuments({_id:/^lab6-seed-page-/})
db.visitor_feedback.countDocuments({_id:/^lab6-seed-feedback-/})
db.visitor_feedback.getIndexes().map(i=>i.name)
```

**Ожидание:** данные/индексы сохранились, bootstrap не переинициализировал rs0. Любая обязательная ошибка даёт ненулевой exit code. `check --with-failover` требует завершённый реальный failover, обычный check позволяет работать без остановки лидера.

**Критерий:** по каждому требованию есть исполняемый сценарий, assertion результата и реальный артефакт. Диагностические журналы содержат и неуспешные попытки разработки; они не выдаются за успешные результаты. Отчёт последней приёмки — `docs/lab6/validation.md`. Не показывайте пароли, не используйте `down -v`, `dropDatabase` или force-reconfig.
