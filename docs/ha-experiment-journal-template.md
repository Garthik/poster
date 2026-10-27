# Журнал экспериментальных отказов (заполнить после запуска)

Дата и окружение: _________________________

| Сценарий | Команда / действие | Ожидаемое поведение | Фактическое наблюдение / ссылка на log |
|---|---|---|---|
| Проверка направленности репликации | `./scripts/ha.sh status`, INSERT через proxy, SELECT на replica | primary writable; replica read-only; запись доставлена | ___ |
| Остановка standby | `docker compose -f docker-compose.ha.yml --profile replica stop replica` | приложение продолжает писать на primary | ___ |
| Возобновление standby | `./scripts/ha.sh replica` | WAL догоняется, новая запись видна на replica | ___ |
| Остановка primary | `./scripts/ha.sh watch --daemon` + `docker compose ... stop primary` | краткий сбой/переподключение, promotion replica | ___ |
| После переключения | INSERT через proxy, SELECT на replica (теперь primary) | запись успешна; старый primary fenced | ___ |
| Backup/restore | `./scripts/ha.sh backup`, `./scripts/ha.sh restore` | независимая чистая БД имеет данные дампа | ___ |
| TLS | `./scripts/ha.sh check` | verify-full принят, sslmode=disable отвергнут | ___ |
| Lag | `./scripts/ha.sh lag load` | CSV с измерениями lag | ___ |

Замечания, временные метки и восстановления: _______________________________________________
