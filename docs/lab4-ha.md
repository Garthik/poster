# Лабораторная №4 — доступы, backup/restore, TLS и репликация PostgreSQL

## Что именно сделано

Добавлен **самостоятельный** HA-контур для существующей схемы `app` билетной платформы (без переписывания миграций ЛР2/ЛР3):

- `primary`: PostgreSQL 16, запись, порт хоста `127.0.0.1:5434`;
- `replica`: PostgreSQL 16, асинхронная физическая streaming replication, чтение, `127.0.0.1:5435`;
- `proxy`: HAProxy, единая точка подключения приложения `127.0.0.1:5436`;
- `restore`: отдельный **чистый** PostgreSQL на `127.0.0.1:5437` (запускается только на восстановление);
- отдельные логины `ticket_admin`, `ticket_app`, `ticket_analyst` и техническая роль `ticket_replication`;
- TLS-сертификаты с локальным CA; `hostnossl ... reject` + `scram-sha-256`;
- `pg_dump` custom format, `pg_restore`, HA-watch, проверка прав, измерение lag, журналы отказов.

**ВАЖНО:** ранее использовавшийся `docker-compose.yml` предназначен для старых лабораторных и содержит прежний демонстрационный суперпользовательский `ticket_app`. В ЛР4 **НЕ** используйте `make up` или `docker compose up` без `-f docker-compose.ha.yml`: такой режим не удовлетворяет требованиям безопасности. Для ЛР4 запускайте **только** `./scripts/ha.sh` / цели `make ha-*`.

В задании упомянут «предоставленный инфраструктурный шаблон», но сам шаблон в материалах отсутствовал, поэтому приложен работающий самостоятельно `docker-compose.ha.yml`. Если преподаватель выдаст другой шаблон, параметры доступа/репликации нужно перенести в него.

## Зависимости и подготовка

WSL Ubuntu, работающий Docker Desktop / Docker Engine + Compose, `psql`, `pg_dump`, `pg_restore`, `openssl`, `bash`. Важно: из WSL порты `5434–5437` должны быть свободны. Если старый контейнер ещё занимает `5434`, остановить его **без удаления volume**:

```bash
# Из корня ticket-platform-lab4:
docker compose -f docker-compose.yml down
```

### Первый старт (команды в указанном порядке)

```bash
./scripts/ha.sh init            # секреты + CA ВНЕ репозитория
./scripts/ha.sh up              # primary + proxy, ожидание готовности
./scripts/ha.sh roles           # роли, парольные политики, WAL-слот
./scripts/ha.sh migrate         # старые миграции как ticket_admin + grants.sql
./scripts/ha.sh seed            # базовый набор ЛР2/3
./scripts/ha.sh replica         # pg_basebackup, standby.signal, WAL streaming
./scripts/ha.sh status          # проверка pg_is_in_recovery, pg_stat_replication
./scripts/ha.sh replcheck       # INSERT через proxy, SELECT на replica + отказ записи на standby
./scripts/ha.sh check           # положительные/отрицательные проверки прав и TLS
```

> `make ha-init`, `make ha-up`, `make ha-roles` и другие цели дают тот же эффект.

### Добавить сгенерированные данные текущего проекта

```bash
./scripts/ha.sh app ./scripts/generate_data.sh development
# Нагрузочный запуск создаёт 3 000 000 сканов:
./scripts/ha.sh app ./scripts/generate_data.sh load
```

Оба варианта выполняются под **ticket_app**, не под суперпользователем, через HAProxy + `sslmode=verify-full`.

## Проверка прав ролей

| Роль | Разрешено | Запрещено |
|---|---|---|
| `ticket_admin` | создание/изменение объектов `app`, миграции, чтение и изменение всех бизнес-таблиц | операции суперпользователя, создание кластерных ролей |
| `ticket_app` | DML над перечисленными бизнес-таблицами и выполнение бизнес-функций, чтение последовательностей | `CREATE ROLE`, `CREATE TABLE`, доступ к `app.schema_migrations`, superuser |
| `ticket_analyst` | SELECT бизнес-таблиц, отдельные поля `users` без `password_hash` | INSERT/UPDATE/DELETE, DDL, чтение `password_hash` |
| `ticket_replication` | только REPLICATION и TLS | обычный прикладной DML |

SQL-источники: `infra/ha/roles.sql` и `infra/ha/grants.sql`.

```bash
./scripts/ha.sh check
cat artifacts/ha/security_checks.txt
cat artifacts/ha/denied_last.txt
```

`check` реально отправляет запрещённые команды и **считает успехом только отказ**. В логах сохраняются PASS/FAIL, пароль не печатается.

## Секреты и SSL/TLS

Секреты создаются не в репозитории, а по умолчанию в:

```text
~/.local/share/ticket-platform-ha/
├── primary.env
├── roles.env
├── replica.env
├── routing.env
├── tls/{ca.crt,ca.key,primary/,replica/} (каждому серверу монтируется только его ключ)
├── state/
└── backups/
```

Каталоги имеют права `0700`, файлы паролей и закрытые ключи — `0600`. Сертификаты (не секреты) могут читаться сервером. `.gitignore` исключает env, приватные ключи, дампы, `artifacts/`. `POSTGRES_PASSWORD` для технического bootstrap-аккаунта также читается контейнером из внешнего `primary.env`. Локальный CA создан для учебного контура, **это не публично доверенный production CA**. Не добавляйте credentials, приватные ключи и backup в репозиторий, скриншоты/отчёт или общедоступную документацию.

```bash
./scripts/ha.sh check       # TLS verify-full подтверждается через pg_stat_ssl
# sslmode=disable должен быть отвергнут pg_hba.conf
```

При подключении pgAdmin к HA-контру: host=`localhost`, port=`5436`, user=`ticket_analyst` или `ticket_admin`, SSL mode=`verify-full`, root cert=`~/.local/share/ticket-platform-ha/tls/ca.crt`, пароль берётся только из локального внешнего секретного файла (не показывать в отчёте). TLS завершается на PostgreSQL: HAProxy прозрачно передаёт TCP.

## Резервная копия и восстановление

```bash
./scripts/ha.sh backup
./scripts/ha.sh restore
```

`backup` использует `pg_dump -Fc --no-owner --no-acl` через proxy/TLS и проверяет архив `pg_restore --list`. Бэкап сохраняется **вне репозитория**, в `.../backups/*.dump`.

`restore` стартует PostgreSQL c отдельным новым volume `ha_restore` и выполняет `pg_restore --no-owner --no-acl` от имени bootstrap-администратора. Скрипт удаляет только старый **restore-volume**, не primary и не replica; затем показывает количество строк из `app.events`, `app.orders`, `app.tickets`, `app.ticket_scans`. Если после backup были новые записи, числа живого источника могут отличаться, это нормально.

## Доказательство направления репликации

```bash
./scripts/ha.sh status
```

На **primary** `pg_is_in_recovery() = false`, есть строка `pg_stat_replication` с `application_name=ticket_replica`, обычно `state=streaming`. На **replica** `pg_is_in_recovery() = true` и `pg_last_wal_receive_lsn()` / `pg_last_wal_replay_lsn()` растут.

Запись добавляется **через приложение/HAProxy**; запрос на replica убеждается, что она появилась. Отдельная безопасная команда: `./scripts/ha.sh replcheck` (лог `artifacts/ha/replication_verification.log`). Этот же сценарий включён в `./scripts/ha.sh demo`.

> Физическая реплика **read-only** до promotion. Запись на неё должна отклоняться: нельзя считать два независимых контейнера репликацией.

## Измерение replication lag при массовой загрузке

```bash
./scripts/ha.sh lag development  # короткая массовая загрузка на 75 000 строк
./scripts/ha.sh lag load         # полная массовая загрузка на 3 млн строк
```

Во время генерации `lag.sh` опрашивает `pg_stat_replication`: расстояние LSN в байтах `pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)` и временные метрики `write_lag`, `flush_lag`, `replay_lag`, если доступны. Результат сохраняется в `artifacts/ha/replication_lag_<mode>.csv`; временные метрики PostgreSQL могут содержать NULL в моменты простоя. Для большого единственного транзакционного COMMIT особенно важны отсчёты **после COMMIT**. В async replication RPO не равен строго нулю.

## Эксперименты с отказами

**Остановка replica:**

```bash
# Для проверки в demo эта последовательность выполняется автоматически:
./scripts/ha.sh demo
```

`demo` сначала проверяет права/TLS и restore, затем добавляет запись и проверяет её на replica; останавливает replica и пишет новую запись через proxy; запускает replica заново и ждёт доставки записи.

**Остановка primary:** перед остановкой запускается фоновый watcher (`watch --daemon`), затем `docker compose ... stop primary`. Три неуспешных health probe приводят к `pg_promote(wait=true)` на replica, созданию защитной отметки `state/failover.lock` и пересозданию HAProxy с новым backend. Новые подключения приложения после короткого окна ошибок опять проходят через тот же `localhost:5436`. Фактический лог probe — `artifacts/ha/app_probe.log`, диагностический журнал — `artifacts/ha/failure_experiments.log`.

**ПРЕДУПРЕЖДЕНИЕ:** `demo` **останавливает primary и переводит replica в роль нового primary**. Это тест аварийного переключения, его следует запускать **последним**, на отдельном учебном стенде, после всех тестов нагрузки. Возврат исходного primary невозможен простым `docker start`: он защищён `failover.lock`. Для восстановления резервного узла требуется пересоздание данных старого primary из нового primary либо применение `pg_rewind` после проверки WAL timeline. Не снимайте lock до устранения риска split brain.

## Файлы для сдачи

- `infra/ha/roles.sql`, `infra/ha/grants.sql`, `infra/ha/pg_hba.conf` — права и политики;
- `scripts/ha/init_secrets.sh`, этот документ — секреты и TLS;
- `scripts/ha/backup.sh`, `scripts/ha/restore.sh` — резервная копия и restore;
- `docker-compose.ha.yml`, `infra/ha/start-primary.sh`, `infra/ha/start-replica.sh` — потоковая репликация;
- `scripts/ha/demo.sh`, `artifacts/ha/failure_experiments.log` — реальные отказные эксперименты;
- `docs/ha-runbook.md` — действия оператора;
- `scripts/ha/watch.sh`, `scripts/ha/failover.sh`, `infra/ha/haproxy.cfg.tpl` — failover и восстановление клиентского подключения;
- `scripts/ha/lag.sh`, `artifacts/ha/replication_lag_load.csv` — измерение lag.

`artifacts/ha/*` формируется во время **фактического запуска** на вашей машине; архив исходников не содержит выдуманных логов или результатов.
