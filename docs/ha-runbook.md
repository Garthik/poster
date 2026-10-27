# Runbook — PostgreSQL TicketPlatform (primary / replica / HAProxy)

## 1. Признаки неисправности

- Приложение через `localhost:5436` получает `connection refused`, `server closed connection` или timeout.
- Нет актуальных данных на `replica`; растёт разница LSN на `primary`.
- В `pg_stat_replication` нет `ticket_replica`, либо `state` не `streaming`.
- В логах Docker ошибки TLS, аутентификации, WAL или невозможность восстановить связь с primary.

## 2. Диагностика (без изменения данных)

```bash
./scripts/ha.sh status
export TICKET_SECRETS_DIR="$HOME/.local/share/ticket-platform-ha"
docker compose -f docker-compose.ha.yml --profile replica ps
docker compose -f docker-compose.ha.yml logs --tail=80 primary replica proxy
cat "$TICKET_SECRETS_DIR/routing.env"
```

На ожидаемом primary: `SELECT pg_is_in_recovery()` → `false`; на standby → `true`.

SQL для primary:

```sql
SELECT application_name, state, sync_state,
       sent_lsn, write_lsn, flush_lsn, replay_lsn,
       write_lag, flush_lag, replay_lag
FROM pg_stat_replication;

SELECT slot_name, active, restart_lsn,
       wal_status, safe_wal_size
FROM pg_replication_slots;
```

SQL для replica:

```sql
SELECT pg_is_in_recovery(),
       pg_last_wal_receive_lsn(),
       pg_last_wal_replay_lsn(),
       pg_last_xact_replay_timestamp();
```

## 3. Остановлена только replica

**Поведение:** приложение через HAProxy остаётся подключено к primary, запись продолжается; чтение через replica недоступно. При использовании physical slot WAL на primary копится; `max_slot_wal_keep_size=2GB` ограничивает сохранение и может потребовать полной пересборки replica после долгого простоя.

1. Посмотреть `docker compose ... logs replica` и доступное место на primary.
2. Запустить `./scripts/ha.sh replica` (не удаляет replica volume).
3. Проверить, что `pg_is_in_recovery()=true`, `pg_stat_replication.state=streaming`.
4. Убедиться, что новая запись через приложение появится на replica.
5. Если нужные сегменты WAL утрачены, остановить replica и пересоздать **только её volume** из нового `pg_basebackup` (операция разрушает старую копию replica; выполнять после проверки primary и резервной копии).

## 4. Остановлен primary

**Поведение:** HAProxy какое-то время не принимает новые успешные SQL-запросы, текущие соединения рвутся. Клиент должен переподключаться с backoff/retry. При рабочей standby автоматический watcher после трёх неудачных проб выполнит promotion и переведёт HAProxy на неё.

1. Проверить фактическую недоступность старого primary; убедиться, что он **остановлен/изолирован**, а не просто есть сетевая задержка.
2. Запустить наблюдатель **заранее**: `./scripts/ha.sh watch --daemon`. Для управляемого переключения после остановки можно использовать `./scripts/ha.sh failover`.
3. Посмотреть `cat artifacts/ha/failure_experiments.log` и `cat "$TICKET_SECRETS_DIR/routing.env"` (`TICKET_ACTIVE_DB=replica`).
4. Через proxy выполнить `SELECT pg_is_in_recovery()`; после переключения результат `false`.
5. Выполнить через пользователя приложения INSERT в `app.venues`, затем SELECT по этой записи.
6. **Не запускать бывший primary как самостоятельный writable узел:** файл `state/failover.lock` блокирует старт старой primary-службы. Требуется пересоздать старый узел как новую standby или использовать `pg_rewind` при соблюдении предпосылок. Автоматического failback в учебном стенде нет.

**Безопасность:** локальный watcher и файловый lock достаточны для управляемого отказа `docker compose stop primary` на одной машине, но **не являются распределённым fencing/STONITH** для сетевого split brain. Для production используйте Patroni/etcd и внешний fencing.

## 5. Backup/Restore при повреждении данных

```bash
./scripts/ha.sh backup
./scripts/ha.sh restore
```

Restore выполняется в **чистый отдельный экземпляр**, не затирает primary. Выберите валидный dump, просмотрите `artifacts/ha/restore.log`; сопоставьте счётчики `events`, `orders`, `tickets`, `ticket_scans`, дополнительные FK CHECK и ожидаемые бизнес-данные.

При реальной аварии: не восстанавливайте в действующий primary без остановки записей, фиксирования текущего состояния и решения о RPO/RTO. Если backup старше последней записи, восстановление приводит к потере более новых данных.

## 6. Проверка целостности и завершение

```sql
SELECT count(*) FROM app.events;
SELECT count(*) FROM app.orders;
SELECT count(*) FROM app.tickets;
SELECT count(*) FROM app.ticket_scans;
SELECT count(*) AS broken_ticket_fk
FROM app.ticket_scans s
LEFT JOIN app.tickets t ON t.id=s.ticket_id
WHERE t.id IS NULL;
```

Ожидается `broken_ticket_fk=0`. Запустите `./scripts/ha.sh check`, проверьте чтение/запись приложения и наличие наблюдения/backup после возвращения к стабильной топологии.

## 7. Журнал экспериментов

Фактические результаты скриптов:
- `artifacts/ha/failure_experiments.log`;
- `artifacts/ha/app_probe.log`;
- `artifacts/ha/security_checks.txt`;
- `artifacts/ha/restore.log`;
- `artifacts/ha/replication_lag_load.csv`.

**Не подменяйте эти файлы шаблонными значениями в отчёте.**
