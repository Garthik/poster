# Sprint 6: MongoDB — индексы, Bulk API, транзакции, репликация

Расширение существующей документной модели Sprint 5. PostgreSQL 16 остаётся источником истины для мероприятий, билетов, платежей и заказов. Используются **те же поля и валидаторы** `mongo/schema.js`, но отдельный Compose-проект `ticket-platform-lab6`. Standalone MongoDB Lab5, PostgreSQL HA, их данные, секреты и тома не изменяются.

## Быстрый запуск в WSL2 Ubuntu

Нужны Docker Engine + Compose v2, Bash, `openssl`, `flock` (util-linux), свободные loopback-порты 27101–27103 и около 3 GB доступной памяти для стенда. Каждый mongod ограничен 768 MB, WiredTiger cache — 256 MB. Node.js на хосте не нужен: официальный драйвер `mongodb` **6.21.0** и Node.js 22 запускаются в контейнере runner. Версии транзитивных пакетов зафиксированы в `mongo/lab6/package-lock.json`; сборка использует `npm ci`.

```bash
cd /mnt/c/TomeD/VSCode/Proga/Afisha/poster
bash scripts/lab6.sh init
bash scripts/lab6.sh all
# Отдельный, явно запрошенный эксперимент с остановкой PRIMARY:
bash scripts/lab6.sh failover --yes
bash scripts/lab6.sh check --with-failover
```

`all` запускает `up → seed → benchmark → bulk → transaction → index-write → test → check`. Он не останавливает PRIMARY и не удаляет тома. Тесты создают и убирают только принадлежащие Lab6 временные документы. Детерминированный seed остаётся для explain/защиты; его повторный запуск заменяет только документы `lab6-seed-*`. Не запускайте другие клиенты, меняющие эти тестовые ID, параллельно с измерениями. Скрипт защищён от параллельных запусков через `flock`.

`up` применяет `--no-recreate`: повторная команда не пересоздаёт уже работающие mongod даже при изменении Compose-файла. Для осознанного применения изменённой конфигурации сначала выполните отдельный `down`, затем `up`; тома сохранятся. Runner при `up` пересобирается из текущего кода.

Для заполнения используется уже имеющийся `artifacts/lab5/pg_events.json` — экспорт реальных ID PostgreSQL из Lab5. Если файла нет, сначала выполните `bash scripts/lab5.sh sync` в настроенном окружении Lab5. Страницы Lab6 — редакционные тестовые проекции этих ID, не новые мероприятия и не перенос источника истины. Исходный standalone не копируется и не очищается.

## Команды

|Команда `bash scripts/lab6.sh …`|Действие|
|---|---|
|`init`|Локальные root/app credentials и keyfile; существующие не перезаписываются|
|`up`|Три `mongo:7.0`, выборы, application user, схема Lab5, сборка runner, проверка 1+2|
|`status`|Реальный `replSetGetStatus`, имена, health, три голосующих data-bearing участника|
|`seed`|12 000 страниц + 60 000 отзывов, seed `20261104`, SHA256|
|`benchmark`|Два реальных запроса, 3 прогрева и ≥5 explain до/после|
|`bulk`|1002 операции, 1000 успехов, ожидаемые 121/11000, replay и уборка|
|`transaction`|COMMIT, ROLLBACK, серверные error labels, потерянный commit reply, replay|
|`index-write`|Вставка/обновление одинаковых 6000 документов, ≥5 повторов, collStats|
|`test`|Unit-тесты медиан, планов, seed и границ retry; БД не требуется|
|`check`|Повторная семантическая проверка сырых данных и состояния живой БД|
|`failover --yes`|Остановка динамически найденного PRIMARY, новый PRIMARY, восстановление клиента и узла|
|`check --with-failover`|Дополнительно требует успешный фактический failover-отчёт|
|`shell mongo2`|Аутентифицированный интерактивный mongosh, без пароля в argv|
|`down`|Остановка только Lab6 с сохранением всех томов|

`status` ждёт **полностью здоровый** кластер; при аварии воспользуйтесь runbook. Для изменения объёма до `all` можно экспортировать `LAB6_SEED`, `LAB6_PAGE_COUNT` (≥1000), `LAB6_FEEDBACK_COUNT` (≥10000), `LAB6_WRITE_COUNT` (≥1000), `LAB6_RUNS` (≥5). После изменения seed запустите все связанные измерения заново: `check` проверяет связь с SHA256 исходного набора.

## Доступ из Docker и WSL

Внутри Compose runner использует `mongodb://mongo1:27101,mongo2:27102,mongo3:27103/?replicaSet=rs0&retryWrites=true`; credentials передаются через `auth`, отдельно от URI. DNS Compose разрешает все имена. У каждого участника внутренний порт совпадает с опубликованным loopback-портом WSL. Lab5 использует другой порт `27018`.

Для **необязательного** запуска драйвера прямо в WSL добавьте в `/etc/hosts` (редактировать только один раз):

```text
127.0.0.1 mongo1 mongo2 mongo3
```

При установленном Node.js ≥22:

```bash
npm ci --prefix mongo/lab6 --ignore-scripts
export LAB6_SECRET_DIR="${TICKET_SECRETS_DIR:-$HOME/.local/share/ticket-platform-ha}/lab6"
node mongo/lab6/cli.mjs status
```

Подключение только к `localhost:27101` без разрешения **всех объявленных имён** не обеспечивает работу replica-set discovery. Для основного контейнерного сценария `/etc/hosts` менять не нужно. Доступ напрямую из Windows отдельно не настраивается; основная поддерживаемая среда — WSL и Compose.

## Секреты и границы стенда

`~/.local/share/ticket-platform-ha/lab6/` (или `$TICKET_SECRETS_DIR/lab6/`) содержит `root-user`, `root-password`, `app-password`, `rs-keyfile`. Каталог `0700`, файлы `0600`. `init` отвергает хранение в репозитории и `/mnt/*`. Keyfile копируется внутри каждого контейнера как `mongodb:mongodb`, `0400`. Пароли не передаются в аргументах mongosh и не записываются в артефакты.

Application user имеет `readWrite` только в `ticket_platform_docs` и `clusterMonitor`. Root нужен контроллеру для bootstrap, проверки конфигурации и `failCommand`. `enableTestCommands=1` включён **на отдельном учебном наборе** для воспроизводимых ошибок транзакций. TLS для MongoDB в этом спринте не реализован; published ports ограничены loopback, внутренний keyfile аутентифицирует участников. Это не production-конфигурация.

## Файлы и результаты

- `docker-compose.lab6.yml`, `scripts/lab6.sh`, `scripts/lab6/` — инфраструктура и управление.
- `mongo/lab6/` — официальный драйвер, сценарии, bootstrap; `tests/lab6/` — unit-тесты.
- `artifacts/lab6/` — реальные полные планы, CSV, JSON, Markdown, TAP и диагностические логи.
- [Методика и результаты](benchmark.md), [архитектура](architecture.md), [транзакции](transactions.md), [concerns](concerns.md), [runbook](failover-runbook.md), [подробная защита](demo.md).
- `ticket-platform-lab6-demonstration-guide.html` в корне — автономная инструкция по образцу HTML Lab5: 16 этапов, боковая навигация, поиск, копирование команд, сохраняемый прогресс и печать/PDF. `demonstration-guide-lab6.html` содержит ту же версию для совместимости прежних ссылок. Пересборка: `node scripts/lab6/build-guide.mjs`; Node.js нужен только для пересборки, открытие HTML не требует сети или установки пакетов.

При провале обязательной проверки возвращается ненулевой exit code; `PASS` печатается после проверок результата. Условия failover включены только при `--with-failover`, а не подменяются проверкой наличия контейнеров. Повторно запустить их можно без удаления данных.
