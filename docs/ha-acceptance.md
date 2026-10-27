# Критерии приёмки — ЛР4

- [ ] `./scripts/ha.sh check`: ticket_app запрещён CREATE ROLE / CREATE TABLE, ticket_analyst не может INSERT/читать password_hash, ticket_admin может CREATE TABLE app.
- [ ] `./scripts/ha.sh check`: `pg_stat_ssl.ssl=true`, отключённый SSL отвергается.
- [ ] `./scripts/ha.sh backup` + `./scripts/ha.sh restore`: дамп восстановлен на другом чистом экземпляре, сравнили бизнес-данные.
- [ ] `./scripts/ha.sh status`: на primary `pg_is_in_recovery=false`, replica `true`; `pg_stat_replication.state=streaming`.
- [ ] Добавлена новая запись через HAProxy; прочитана с replica (`./scripts/ha.sh replcheck`), standby отвергает INSERT.
- [ ] Остановка replica: primary продолжает принимать запись, replica после запуска догоняет.
- [ ] Остановка primary: watcher продвигает replica; HAProxy перенаправляет новые подключения, приложение восстанавливается.
- [ ] `./scripts/ha.sh lag load` сохраняет CSV с метриками и замерами после COMMIT.
- [ ] Журнал отказов и runbook оформлены и подтверждены реальными наблюдениями.

**Рекомендуемый порядок:** сначала `init/up/roles/migrate/seed/replica/check/lag/backup/restore`, после них `demo`. Демонстрация `demo` выполняет аварийное promotion и меняет роли узлов; запускайте её в конце.
