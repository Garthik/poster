# Отказ PRIMARY: проведение и восстановление

## Подготовка и подтверждение

Это **отдельный нарушающий доступность эксперимент** только в Compose-проекте Lab6. `all` его не запускает. Ключ `--yes` явно подтверждает остановку текущего PRIMARY. На рабочей демонстрации запускайте последним; запущенные вне скрипта операции Lab6 могут получить временные ошибки.

```bash
bash scripts/lab6.sh all
bash scripts/lab6.sh failover --yes
bash scripts/lab6.sh check --with-failover
```

`scripts/lab6/failover.sh` сначала требует 1 PRIMARY + 2 SECONDARY. Долгоживущий `failover-client` открывает официальный MongoClient с **полной replica-set URI**, выполняет majority write/read и публикует имя актуального primary. Bash проверяет разрешённое имя `mongo1|mongo2|mongo3`, останавливает именно этот сервис и ждёт сигнал восстановления приложения. Не предполагается, что mongo1 — лидер.

Клиент с тем же объектом MongoClient ждёт другой primary, читает подтверждённый до сбоя документ, записывает новый и читает его обратно. Только после этих проверок Bash возвращает прежний узел. Клиент проверяет его `SECONDARY`, health и **наличие новой записи непосредственно на этом узле**. Тестовые документы очищаются, сохраняются `artifacts/lab6/failover.json` и `logs/failover-client.log`.

В `finally`/EXIT trap скрипт пытается запустить остановленный сервис даже при провале. При timeout/ошибке контейнерный runner убирается, но данные и volumes сохраняются. IPC-файлы находятся в игнорируемом `artifacts/lab6/control/`; они не заменяют итоговый JSON и не являются доказательством успеха. `flock` исключает одновременные штатные сценарии.

## Условия PASS

1. PRIMARY до и после отличается; в отчёте есть оба адреса.
2. Driver topology действительно увидела нового PRIMARY.
3. Доаварийная majority-запись сохранилась.
4. Тот же клиент выполнил новую запись и чтение через replica-set discovery.
5. Остановленный участник вернулся SECONDARY и содержит запись, сделанную во время его отсутствия.
6. Временные документы очищены; итоговый процесс и `check --with-failover` вернули 0.

`recoveryMillis` измеряется клиентом после сигнала завершения остановки; это не полное клиентское время недоступности и не SLA. Штатный `docker stop` — контролируемая остановка, не имитация повреждения диска или сетевой partition. Потеря большинства обсуждается теоретически; два узла автоматически не останавливаются.

## Диагностика

```bash
# Для прямых compose-команд экспортируйте только ПУТЬ, не содержимое секретов:
export TICKET_SECRETS_DIR="${TICKET_SECRETS_DIR:-$HOME/.local/share/ticket-platform-ha}"
docker compose -f docker-compose.lab6.yml ps -a
docker compose -f docker-compose.lab6.yml logs --tail 100 mongo1 mongo2 mongo3
bash scripts/lab6.sh shell mongo2
```

В mongosh:

```javascript
db.hello()
db.getSiblingDB('admin').runCommand({replSetGetStatus:1})
db.getSiblingDB('admin').runCommand({replSetGetConfig:1})
```

`status` ожидает полностью здоровый набор, поэтому при остановленном узле диагностируйте через `shell` выжившего, а не ждите успешного `status`. Проверьте `health`, `stateStr`, `lastHeartbeatMessage`, `term`, `optimeDate`, `primary` и `members[].host`.

- `ENOTFOUND mongo2`: запускать runner в Compose либо добавить все три имени в `/etc/hosts` WSL. `directConnection=true` к одному узлу не заменяет replica-set URI приложения.
- Ошибка keyfile permissions: секреты должны быть на Linux filesystem WSL; контейнер копирует keyfile с `0400`, принадлежность `mongodb`. Не делать исходные секреты общедоступными.
- Authentication failed после замены файлов: вернуть прежние credentials. `init` не ротирует пользователей и не лечит несовпадение паролей; не удалять тома.
- Нет PRIMARY при одном работающем узле: восстановить ещё хотя бы один исходный участник для большинства. Не применять force reconfig как обычное «исправление».
- После прерывания fault-injection можно выключить failpoint в shell текущего PRIMARY: `db.getSiblingDB('admin').runCommand({configureFailPoint:'failCommand',mode:'off'})`.

## Восстановление после прерывания

```bash
export TICKET_SECRETS_DIR="${TICKET_SECRETS_DIR:-$HOME/.local/share/ticket-platform-ha}"
docker compose -f docker-compose.lab6.yml start mongo1 mongo2 mongo3
bash scripts/lab6.sh status
# Если runner ещё существует, его имя видно в ps -a; завершите только Lab6 runner.
# Затем повторите подтверждённый эксперимент:
bash scripts/lab6.sh failover --yes
```

`bash scripts/lab6.sh down` останавливает отдельный Lab6 и оставляет тома. Последующий `up` использует прежние данные и конфигурацию. Не применять `down -v`, удаление каталогов данных или принудительную смену rs0. Резервирование не заменяет резервное копирование.
