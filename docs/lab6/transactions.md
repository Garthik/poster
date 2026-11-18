# Атомарная публикация и безопасные повторы

`mongo/lab6/transactions.mjs` экспортирует `publish()`. Страница мероприятия получает `status:'published'` и добавляется через `$addToSet` в `editorial_collections.pageSlugs`. Без транзакции падение между записями оставило бы страницу опубликованной без ссылки в подборке. Обе коллекции редакционные; PostgreSQL в операцию не входит.

## Содержимое одной транзакции

1. Найти receipt по стабильному `operationId`. Если уже есть, сверить `pageSlug/collectionId` и вернуть `alreadyApplied:true`; переиспользование ID с другим payload запрещено.
2. Прочитать страницу и подборку с одной session/snapshot. Проверить существование, summary/sections, лимит 20 ссылок и отсутствие отсутствующих страниц в подборке.
3. Изменить status страницы.
4. Добавить страницу в подборку через `$addToSet`.
5. Вставить receipt в `lab6_publication_operations`, `_id = operationId` (уникальный системный индекс).
6. Commit с majority + journal. Receipt коммитится атомарно с двумя бизнес-документами.

Валидатор Lab5 дополнительно проверяет published-поля и уникальность массива. При конкурентной модификации write conflict приводит к повтору со свежим snapshot. Записи одного receipt и страниц конфликтуют, а уникальный `_id` защищает идентичность операции. Внутри session операции выполняются последовательно; внешних побочных эффектов в callback нет.

## Core API и границы повторов

`transaction-retry.mjs`: `ClientSession.startTransaction()` с `readConcern:'snapshot'`, `writeConcern:{w:'majority',j:true,wtimeoutMS:15000}`, `readPreference:'primary'`, `maxCommitTimeMS:15000`.

- `TransientTransactionError`: abort, затем **весь callback** заново, максимум 4 попытки.
- `UnknownTransactionCommitResult`: повтор **commit той же session/transaction**, максимум 5 попыток. Callback не запускается заново из-за неопределённого commit.
- При исчерпании неизвестных commit-результатов выбрасывается `CommitUncertainError` со стабильным operation ID. Проверить receipt; запрос повторять только с тем же ID. Нельзя сообщать пользователю, что публикация точно отменена.
- При обычной бизнес-ошибке — abort и ненулевой exit code без retry. Короткий ограниченный backoff между повторами; число попыток конечно.

Таймаут записи сам по себе не доказывает откат: подтверждение могло потеряться. Receipt решает прикладную идемпотентность при повторном запросе; `$addToSet` защищает от дублирования связи даже с другой операцией. Это не общая exactly-once гарантия для внешних сервисов.

## Что действительно проверяет сценарий

```bash
bash scripts/lab6.sh transaction
cat artifacts/lab6/transactions.json
bash scripts/lab6.sh test
```

COMMIT проверяет status, ровно одну ссылку и receipt. Повтор с тем же ID проверяет `alreadyApplied`. Контролируемая ошибка возникает после **фактической первой записи**, причём внутри session уже виден published, а снаружи остаётся draft. После abort полные снимки обеих коллекций равны исходным; receipt отсутствует.

Для временных ошибок root-контроллер включает настоящий MongoDB `failCommand` на PRIMARY, с фильтром `appName` конкретного тестового клиента:

- одна серверная ошибка 112 на `update` с `TransientTransactionError` — две попытки всей транзакции;
- одна серверная ошибка 1 на `commitTransaction` с `UnknownTransactionCommitResult` — одна попытка тела, две commit-попытки;
- дополнительный тест сначала реально коммитит, затем скрывает успешный ответ, выбрасывая явно инъецированную клиентскую UnknownCommit-ошибку. Проверяется одна запись тела и безопасный повтор commit, уже после фактического COMMIT.

Failpoint выключается в `finally`; это контролируемые ошибки учебного кластера, а не заявления о случайно наблюдавшемся сетевом сбое. Тест повторов на настоящем failover выполняется отдельно. После сценария временные страницы, подборки и receipts удаляются. В JSON остаются фактические результаты и журнал retry. Unit-тесты дополнительно покрывают исчерпание обоих лимитов, обычную бизнес-ошибку и TTE во время commit.

Для production этот failpoint и `enableTestCommands` следует исключить. [Официальный Core API и error labels драйвера 6.x](https://www.mongodb.com/docs/drivers/node/v6.x/crud/transactions/).
