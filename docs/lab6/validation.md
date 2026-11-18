# Протокол фактической приёмки — 4 ноября 2026

Проверки выполнены в Ubuntu WSL2 на компьютере проекта, через реальный Docker Engine. Ниже зафиксирован последний успешный набор результатов; последующие измерения могут изменить числа. Исходный код SQL, Lab5, HA Compose и их volumes не изменялись. Из ранее существовавших файлов изменены только корневые `README.md` и `.gitignore`.

## Окружение

Полный вывод: [`artifacts/lab6/logs/environment.txt`](../../artifacts/lab6/logs/environment.txt).

- Linux `6.18.54.1-microsoft-standard-WSL2`.
- Docker client/server `29.8.2`, Compose `2.40.3+ds1-0ubuntu1~24.04.1`.
- Фактический MongoDB в образе `mongo:7.0`: **7.0.45**. Repo digest записан в environment.txt.
- Node.js **22.23.4**, официальный `mongodb` **6.21.0**.

## Выполненные команды и результаты

|Проверка|Фактический результат|Доказательство|
|---|---|---|
|`bash scripts/lab6.sh init`|Внешние secrets созданы, существующие Lab4/5 не перезаписаны|`logs/*-init-*.log`|
|`bash scripts/lab6.sh all`, два полных успешных запуска|Оба закончились exit 0; одинаковый SHA256 seed|`logs/*-all-*.log`, `seed.json`|
|Replica Set|Три data-bearing voters; один PRIMARY, два здоровых SECONDARY|`replica-status.json`|
|Два запроса|20 полных explain, 20 измерений, четыре строки медиан, живые индексы проверены|`plans/`, `benchmark/`|
|Bulk|500 inserted + 500 modified, 121 и 11000, 1000 успешных, replay без upsert/modify|`bulk.json`|
|Транзакции|COMMIT, ROLLBACK, TTE attempt=2, UnknownCommit attempt=1/commitAttempts=2, потерянный успешный reply с bodyCalls=1|`transactions.json`|
|Запись/хранилище|Пять INSERT и UPDATE повторов каждой фазы, прогрев, одинаковые 6000 документов|`index-write/`|
|`bash scripts/lab6.sh test`|**10/10** unit-тестов, 0 failures|`unit-tests.tap`|
|`bash scripts/lab6.sh failover --yes`|Весь окончательный сценарий завершился exit 0, включая встроенный check|`logs/*-failover-*.log`, `failover.json`|
|`down → up → check --with-failover`|Те же volumes, документы и индексы сохранены; bootstrap повторяем; exit 0|`logs/*-down-*.log`, `*-up-*.log`, `checks.json`|
|Отказ неаутентифицированного чтения|Код MongoDB **13**, доступа к данным нет|`logs/auth-check.txt`|
|Failover без `--yes`|Exit **2**, PRIMARY не останавливается|`logs/failover-confirmation-guard.txt`|
|Bash syntax|Каждый новый `.sh` разобран `bash -n`, exit 0|`logs/bash-syntax.txt`|
|ShellCheck v0.10.0|Все новые Bash-файлы, exit 0, без предупреждений|`logs/shellcheck.txt`|
|Node syntax|Все `.mjs`, builder HTML и извлечённый inline JS прошли `node --check`|Команды ниже|
|Регрессия Lab5|Статический quality gate прошёл|`logs/lab5-static-checks.txt`|
|HTML по образцу Lab5|16 этапов с навигацией и чекбоксами, 34 блока/кнопки копирования, внешних assets нет; inline JS синтаксически корректен|`logs/html-static-checks.txt`, `guide-script.js`|
|`git diff --check`|Exit 0|Локальная проверка diff|

Пути в последнем столбце, если не указано иначе, относятся к `artifacts/lab6/`. `check.mjs` пересчитывает медианы, сравнивает все полные планы с CSV/JSON и проверяет состояние живой БД; PASS не выводится только на основании существования файлов.

## Последние измерения чтения

|Запрос|Медиана ms до → после|Документов до → после|Ключей до → после|nReturned|
|---|---:|---:|---:|---:|
|Отзывы страницы|2 → 1|593 → 100|593 → 100|100|
|Публикации редактора|20 → 1|9000 → 100|18000 → 100|100|

В обоих случаях до использовался исходный индекс Lab5 с FETCH/IXSCAN/SORT. После — новый индекс Sprint 6, FETCH/IXSCAN/LIMIT без SORT. `pages` исходно **не** использовал COLLSCAN: это установленный фактический план. Исходный `{status,keywords}` — multikey-индекс; число examined keys отличается от числа документов. Это объясняет затраты до оптимизации. В первом успешном прогоне median отзывов была 1 → 1 ms при таком же сокращении документов; ускорение времени не гарантируется.

## Последний эксперимент записи

|Фаза|INSERT median ms|INSERT docs/s|UPDATE median ms|UPDATE docs/s|Index bytes|Storage bytes|
|---|---:|---:|---:|---:|---:|---:|
|Исходные индексы|198.328|30253.0|585.167|10253.5|2781184|4112384|
|Дополнительный Q1-индекс|275.512|21777.7|585.826|10242.0|4763648|4112384|

Logical data bytes в обеих фазах — **2751476**. Дополнительный индекс увеличил выделенные index bytes и в этой серии время INSERT; UPDATE в данной серии почти одинаков. Первые измерения имели другое соотношение времени. Высокие выделенные значения на повторном запуске отражают high-water allocation постоянных экспериментальных коллекций; данные очищаются без drop. Сырые collStats и все повторы сохранены, направление эффекта не подбиралось.

## Подтверждённый отказ

Последний окончательный запуск: **mongo1:27101 → mongo2:27102**. Прежний PRIMARY вернулся SECONDARY и получил запись, созданную во время его остановки. `sameClient`, `beforeWriteSurvived`, `afterWriteRead`, `returnedNodeHasNewWrite` — true. Контейнер клиента завершился с exit 0, OOMKilled=false (`logs/failover-client-state.json`). После полного down/up финальный `check --with-failover` также прошёл.

В процессе разработки сохранены неуспешные bootstrap-попытки и два ранних завершения failover-обёртки: клиент уже записал сигнал завершения и вышел между проверкой файла и `docker inspect`. Ошибка устранена повторной проверкой сигнала после завершения процесса. Эти диагностические логи оставлены, но не выдаются за успешную приёмку. Реальные временные ошибки транзакций вводились серверным failpoint, а потеря уже успешного commit-ответа — отдельно обозначенной клиентской инъекцией.

## Что не проверялось

- Визуальная отрисовка HTML и работа системного clipboard в браузере: Browser Use блокирует протокол `file://`. Обход не выполнялся. HTML проверен статически и пересобирается без зависимостей; откройте `demonstration-guide-lab6.html` обычным браузером для визуального просмотра.
- Прямой Node.js-клиент из WSL с ручным `/etc/hosts`: основной официальный драйвер полностью проверен **в сети Docker**. Ручной прямой путь описан в README, хостовый `/etc/hosts` не изменялся.
- Полные SQL/HA интеграционные сценарии предыдущих лабораторных: PostgreSQL-контейнеры были остановлены до работы. Они не запускались и не изменялись. Статические проверки Lab5 прошли.
- Потеря двух узлов, сетевой partition, повреждение диска, production TLS/backup MongoDB не имитировались. В задании majority loss объяснён теоретически; обязательный одноузловой failover проверен.

## Полный запуск для преподавателя

```bash
cd /mnt/c/TomeD/VSCode/Proga/Afisha/poster
bash scripts/lab6.sh init
bash scripts/lab6.sh all
bash scripts/lab6.sh failover --yes
bash scripts/lab6.sh check --with-failover
```

Дополнительные проверки, если установлен Node.js ≥22 на хосте:

```bash
for f in scripts/lab6.sh scripts/lab6/*.sh mongo/lab6/start-mongo.sh; do bash -n "$f" || exit; done
for f in mongo/lab6/*.mjs tests/lab6/*.mjs scripts/lab6/build-guide.mjs; do node --check "$f" || exit; done
python3 tests/lab5/static_checks.py
node scripts/lab6/build-guide.mjs
python3 tests/lab6/docs_check.py
node --check artifacts/lab6/logs/guide-script.js
docker run --rm -v "$PWD:/mnt:ro" -w /mnt koalaman/shellcheck:v0.10.0 -x \
  scripts/lab6.sh scripts/lab6/*.sh mongo/lab6/start-mongo.sh
git diff --check
```

## Созданные и изменённые файлы

Созданы:

- `.gitattributes`, `docker-compose.lab6.yml`, `demonstration-guide-lab6.html`.
- `scripts/lab6.sh`; `scripts/lab6/lib.sh`, `init.sh`, `failover.sh`, `build-guide.mjs`.
- `mongo/lab6/Dockerfile`, `Dockerfile.dockerignore`, `package.json`, `package-lock.json`, `start-mongo.sh`, `bootstrap.js`, `shell.js`.
- `mongo/lab6/lib.mjs`, `data.mjs`, `seed.mjs`, `benchmark.mjs`, `bulk.mjs`, `transaction-retry.mjs`, `transactions.mjs`, `index-write.mjs`, `cluster.mjs`, `check.mjs`, `cli.mjs`.
- `tests/lab6/metrics.test.mjs`, `retry.test.mjs`, `docs_check.py`.
- `docs/lab6/README.md`, `architecture.md`, `benchmark.md`, `transactions.md`, `concerns.md`, `failover-runbook.md`, `demo.md`, `validation.md`.
- Реальные результаты в `artifacts/lab6/`: 20 JSON explain, 10 JSON collStats, сырые CSV и медианы, Markdown-сводки, seed/bulk/transaction/failover/status/check JSON, TAP и диагностические журналы. Временные IPC, lock и dependencies исключены из Git.

Изменены `README.md` (ссылки и запуск Sprint 6) и `.gitignore` (игнорирование dependencies/IPC). Существующие скрипты и схемы Lab1–5 сохранены.
