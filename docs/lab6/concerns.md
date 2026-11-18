# Read concern, write concern и read preference

Реальные настройки — `mongo/lab6/lib.mjs`, функции `client()` и `TX_OPTIONS`. Они не ограничены текстом инструкции.

|Контекст|readConcern|writeConcern|readPreference|
|---|---|---|---|
|Обычный application client, bulk, критические проверки|`majority`|`w:'majority',j:true,wtimeoutMS:15000`|`primary`|
|Многошаговая публикация|`snapshot`|`w:'majority',j:true,wtimeoutMS:15000` на commit|`primary`|
|Проверка догнавшего узла после failover|`majority`|Записей через него нет|Явное `secondary`, direct connection к возвращённому узлу|

Majority-чтение возвращает majority-committed данные; это не обещание видеть самую последнюю запись всех других клиентов, и не линейризуемость. Для причинно связанного read-your-writes при переключении узлов нужна подходящая causal session и concerns; тесты используют majority-записи и primary-чтение с последовательными подтверждениями.

В наборе из трёх голосующих data-bearing узлов majority — два. Подтверждённая majority-запись существует на большинстве, что снижает риск rollback после выборов, в отличие от подтверждения только прежним PRIMARY. `j:true` требует журналирования; это не замена backup и не защита от потери большинства дисков, административного удаления или ошибок приложения. Write timeout означает отсутствие достаточного подтверждения в срок, а не доказанный откат.

SECONDARY применяет oplog асинхронно, поэтому даже majority-чтение на secondary может видеть более старую majority-committed версию. Для некритичных редакционных витрин можно выбрать `secondaryPreferred` для разгрузки PRIMARY, явно принимая задержку. Для публикации и проверки результата по умолчанию нужен primary. `nearest` выбирает по задержке, а не по свежести; `primaryPreferred` при недоступном PRIMARY способен читать устаревшие данные. Финансовые операции платформы остаются в PostgreSQL.

В транзакции `snapshot` задаёт согласованный снимок для нескольких чтений; majority commit обеспечивает соответствующие гарантии фиксации. Write concern задаётся на транзакции, а не на отдельных её операциях. Все операции получают одну session и выполняются на primary. Ошибки выбора сервера, истечение срока транзакции, write conflict и потеря commit-ответа всё равно возможны — поэтому есть bounded retry и receipt.

`retryWrites=true` помогает повторяемым одиночным операциям драйвера и дополняет, но не заменяет прикладной повтор всей многошаговой транзакции. Таймаут выбора сервера 45 s позволяет переждать короткие выборы, однако не гарантирует отсутствие ошибок при долгой аварии. При потере **двух** из трёх голосующих участников нет большинства; primary не может устойчиво продолжать majority-записи. Read preference не восстанавливает отсутствующий кворум.

Источники: [read concern majority](https://www.mongodb.com/docs/v7.0/reference/read-concern-majority/), [write concern](https://www.mongodb.com/docs/v7.0/reference/write-concern/), [transaction read/write guarantees](https://www.mongodb.com/docs/v7.0/core/transactions/).
