// Rebuild the standalone Sprint 6 guide. Node >=22; no npm/browser dependencies.
// Visual reference: user-supplied ticket-platform-lab5-demonstration-guide.html.
import fs from 'node:fs/promises';
import {fileURLToPath} from 'node:url';

const root = new URL('../../', import.meta.url);
const escape = value => String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;');
const read = name => fs.readFile(new URL(name, root), 'utf8');
async function report(name) {
  try { return JSON.parse(await read('artifacts/lab6/' + name)); }
  catch (error) { if (error.code !== 'ENOENT') throw error; return null; }
}
const [markdown, css, script, bench, write, failover, checks, seed, bulk, tx] = await Promise.all([
  read('docs/lab6/demo.md'), read('scripts/lab6/guide.css'), read('scripts/lab6/guide-ui.js'),
  report('benchmark/results.json'), report('index-write/results.json'), report('failover.json'),
  report('checks.json'), report('seed.json'), report('bulk.json'), report('transactions.json')
]);

function inline(value) {
  const codes = [];
  let html = value.replace(/`([^`]+)`/g, (_, code) => `@@CODE${codes.push('<code>' + escape(code) + '</code>') - 1}@@`);
  html = escape(html).replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  html = html.replace(/\[([^\]]+)\]\(([^)]+)\)/g, (_, label, url) =>
    /^(https?:\/\/|[^:]+$)/.test(url) ? `<a href="${url}">${label}</a>` : label);
  return html.replace(/@@CODE(\d+)@@/g, (_, index) => codes[index]);
}
function command(code, language, label, explanation = '') {
  if (language === 'javascript') code = code.replace(/\n\s+(?=\.)/g, '');
  const shell = language === 'javascript' ? 'mongosh' : language === 'bash' ? 'WSL · Bash' : language;
  return `<div class="command code-block"><div class="commandbar"><span class="commandlabel">${escape(label)}</span><span class="commandkind">${escape(shell)}</span><button class="copy" type="button" aria-label="Копировать: ${escape(label)}">Копировать</button></div><pre><code class="lang-${escape(language)}">${escape(code)}</code></pre></div>` +
    (explanation ? `<p class="command-explain">${inline(explanation)}</p>` : '');
}
const callout = (title, text, kind = 'info') => `<div class="callout ${kind}"><b>${escape(title)}</b><div>${inline(text)}</div></div>`;
function table(headers, rows) {
  return '<div class="tablewrap"><table><thead><tr>' + headers.map(h => '<th>' + escape(h) + '</th>').join('') +
    '</tr></thead><tbody>' + rows.map(row => '<tr>' + row.map(cell => '<td>' + inline(String(cell)) + '</td>').join('') + '</tr>').join('') + '</tbody></table></div>';
}

// Subtitles, file references and command labels make each card reviewable on its own.
const metadata = [
  {title:'Подготовка окружения WSL', sub:'Проверить инструменты, исходный snapshot и границы отдельного стенда', tags:['WSL','подготовка'],
    files:[['docker-compose.lab6.yml','Отдельные сервисы, сеть и тома Lab6'],['docs/lab6/README.md','Требования к окружению и полный запуск']],
    labels:['Проверить рабочий каталог, Docker и исходные данные']},
  {title:'Секреты, запуск и состав Replica Set', sub:'Автоматическая инициализация rs0, auth и три голосующих узла', tags:['Replica Set','auth','rs0'],
    files:[['scripts/lab6/init.sh','Credentials и keyfile вне Git'],['mongo/lab6/bootstrap.js','Инициализация, выбор PRIMARY и схема Lab5']],
    labels:['Подготовить секреты и запустить три узла','Узнать PRIMARY и открыть mongosh','Проверить роли, голоса и валидатор']},
  {title:'Детерминированные данные и реальные поля', sub:'12 000 страниц и 60 000 отзывов; повторяемый seed и SHA256', tags:['seed','Lab5 model'],
    files:[['mongo/lab6/data.mjs','Генератор, фиксированные даты и реальные поля'],['mongo/lab6/seed.mjs','Заполнение только пространства Lab6']],
    labels:['Создать seed и зафиксировать исходный набор','Проверить количество и структуру документов']},
  {title:'Запрос №1: одобренные отзывы страницы', sub:'Сравнить исходный индекс Lab5 с составным индексом сортировки', tags:['explain','IXSCAN','SORT'],
    files:[['mongo/lab6/benchmark.mjs','QUERIES: feedback, equality → sort → tie-break'],['artifacts/lab6/plans/feedback-before-1.json','Полный explain до нового индекса'],['artifacts/lab6/plans/feedback-after-1.json','Полный explain после нового индекса']],
    labels:['Снять измерения и открыть планы Q1','Показать новый индекс и живой explain']},
  {title:'Запрос №2: публикации редактора', sub:'Фильтр по status/editor.alias и сортировка по headline/_id', tags:['compound index','FETCH'],
    files:[['mongo/lab6/benchmark.mjs','QUERIES: pages и новый составной индекс'],['artifacts/lab6/plans/pages-before-1.json','Фактический исходный winning plan'],['artifacts/lab6/plans/pages-after-1.json','План с новым индексом']],
    labels:['Показать исходный и оптимизированный планы Q2','Повторить живой запрос к event_pages']},
  {title:'Серии измерений, CSV и медианы', sub:'Не менее пяти повторов и три прогрева для каждой фазы', tags:['executionStats','median','CSV'],
    files:[['artifacts/lab6/benchmark/measurements.csv','Все сырые измерения'],['artifacts/lab6/benchmark/medians.csv','Четыре медианные строки'],['mongo/lab6/check.mjs','Сверка планов, CSV и пересчёт медиан']],
    labels:['Открыть CSV и проверить результаты автоматически','Вывести четыре метрики executionStats','Пересчитать медианы независимо в Python']},
  {title:'Bulk API: частичные ошибки и replay', sub:'1002 независимые операции; 1000 успехов и две ожидаемые ошибки', tags:['bulkWrite','ordered: false'],
    files:[['mongo/lab6/bulk.mjs','insertOne + updateOne, MongoBulkWriteError и replay'],['artifacts/lab6/bulk.json','Реальные счётчики частичного успеха']],
    labels:['Проверить bulkWrite и повторяемость','Убедиться в уборке и ограничениях rating']},
  {title:'Транзакция: согласованный COMMIT', sub:'Публикация страницы, связь с подборкой и уникальный receipt', tags:['ClientSession','COMMIT','idempotency'],
    files:[['mongo/lab6/transactions.mjs','publish(): две бизнес-коллекции и receipt'],['mongo/lab6/transaction-retry.mjs','Явный Core API с конечными повторами']],
    labels:['Запустить тест публикации и показать отчёт','Показать поля моделей и unique _id receipt']},
  {title:'ROLLBACK после первой записи', sub:'Доказать откат двух коллекций и изоляцию незавершённой записи', tags:['ROLLBACK','snapshot'],
    files:[['mongo/lab6/transactions.mjs','afterFirstWrite и сравнение полных снимков'],['artifacts/lab6/transactions.json','results.rollback: unchangedCollections и receiptAbsent']],
    labels:['Повторить контролируемый rollback-тест','Показать session/snapshot без изменения данных']},
  {title:'Retry при временных ошибках транзакции', sub:'Различать повтор всей операции и повтор только commit', tags:['TTE','UnknownCommit','failCommand'],
    files:[['mongo/lab6/transaction-retry.mjs','runTransaction() и CommitUncertainError'],['tests/lab6/retry.test.mjs','Границы повторов и terminal failures']],
    labels:['Проверить error labels и лимиты retry','Показать выключенный failpoint и уникальность receipt']},
  {title:'Read/Write Concern и Read Preference', sub:'Критичные операции — primary/majority; транзакции — snapshot', tags:['majority','primary','consistency'],
    files:[['mongo/lab6/lib.mjs','Фактические MongoClient options и TX_OPTIONS'],['docs/lab6/concerns.md','Гарантии, задержка secondary и отсутствие большинства']],
    labels:['Открыть действующие настройки клиента','Выполнить majority-read с primary preference']},
  {title:'Цена индекса для записи и хранения', sub:'Одинаковые 6000 документов, INSERT/UPDATE и полные collStats', tags:['write cost','collStats','throughput'],
    files:[['mongo/lab6/index-write.mjs','Прогрев, чередование фаз и обслуживание индекса'],['artifacts/lab6/index-write/summary.md','Медианы, docs/s и выделенное хранилище']],
    labels:['Выполнить эксперимент записи и открыть медианы','Показать индексы и текущие размеры коллекций']},
  {title:'Отказ PRIMARY и восстановление клиента', sub:'Отдельный эксперимент с явным failover --yes', tags:['failover','выборы','SECONDARY'], dangerous:true,
    files:[['scripts/lab6/failover.sh','Динамический PRIMARY и восстановление узла'],['mongo/lab6/cluster.mjs','Тот же MongoClient, новые write/read и catch-up'],['artifacts/lab6/failover.json','Адреса before/after и доказательства восстановления']],
    labels:['Остановить текущий PRIMARY и проверить весь сценарий','Показать новый PRIMARY и здоровые состояния']},
  {title:'Полный прогон и сохранность томов', sub:'Автоматические assertions, unit-тесты и повторный up', tags:['all','check','10 unit tests'],
    files:[['scripts/lab6.sh','Команды all/check; failover запускается отдельно'],['artifacts/lab6/checks.json','Семантическая приёмка последнего запуска'],['docs/lab6/validation.md','Протокол выполненных и пропущенных проверок']],
    labels:['Выполнить полный прогон и итоговую приёмку','Необязательно: остановить Lab6 и поднять прежние тома','Проверить данные и индексы после повторного up']}
];
const headings = [...markdown.matchAll(/^## (\d+)\. (.+)$/gm)];
if (headings.length !== metadata.length) throw new Error('Unexpected structure of docs/lab6/demo.md');

function renderMarkdown(body, meta) {
  const lines = body.split(/\r?\n/), html = [];
  let paragraph = [], codeIndex = 0, criterion = '';
  function flush() {
    if (!paragraph.length) return;
    const value = paragraph.join(' ');
    paragraph = [];
    if (value.startsWith('**Открыть:**')) return;
    if (value.startsWith('**Критерий:**')) { criterion = value.replace('**Критерий:**', '').trim(); return; }
    if (/^\*\*Ожидание[^*]*\*\*/.test(value)) {
      html.push(callout('Ожидаемый результат', value.replace(/^\*\*Ожидание[^*]*\*\*\s*/, '')));
    } else html.push('<p>' + inline(value) + '</p>');
  }
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (line.startsWith('```')) {
      flush();
      const language = line.slice(3).trim(), code = [];
      while (++i < lines.length && !lines[i].startsWith('```')) code.push(lines[i]);
      const label = meta.labels?.[codeIndex++] || (language === 'javascript' ? 'Запросы Mongo Shell' : 'Команды WSL');
      html.push(command(code.join('\n'), language, label));
    } else if (line.startsWith('### ')) { flush(); html.push('<h3>' + inline(line.slice(4)) + '</h3>'); }
    else if (!line.trim()) flush();
    else paragraph.push(line);
  }
  flush();
  return {html:html.join('\n'), criterion};
}

const sections = headings.map((heading, index) => {
  const start = heading.index + heading[0].length;
  let body = markdown.slice(start, headings[index + 1]?.index ?? markdown.length).trim();
  if (index === 0) body = `**Что реализовано:** отдельный Compose-проект ticket-platform-lab6, три новых тома MongoDB и повторное использование схемы Lab5. PostgreSQL и standalone Lab5 не преобразуются в rs0.

Работайте в Ubuntu WSL2 из корня проекта. Нужны Docker Compose v2, Bash, openssl и flock; Node.js для основного сценария запускается внутри runner. Стенду требуется около 3 GB памяти; порты 27101–27103 должны быть свободны.

\`\`\`bash
cd /mnt/c/TomeD/VSCode/Proga/Afisha/poster
pwd
ls scripts/lab6.sh docker-compose.lab6.yml mongo/schema.js
docker version
docker compose version
command -v openssl
command -v flock
test -s artifacts/lab5/pg_events.json
\`\`\`

**Ожидание:** Docker показывает Client и Server; файл pg_events.json непустой. В нём — ID реальных событий, ранее экспортированные Lab5 из PostgreSQL. Если файла нет, выполните Lab5 sync в настроенном окружении; это единственный необходимый снимок PG для данного стенда.

**Критерий:** инструменты доступны, файлы проекта и snapshot присутствуют. Следующий шаг запускает только отдельный MongoDB-стенд Lab6. Пароли и keyfile остаются вне Git.`;
  if (index === 1) body = `\`\`\`bash
bash scripts/lab6.sh init
bash scripts/lab6.sh up
\`\`\`

${body}`;
  if (index === 13) {
    const fence = '```';
    body = body.replace('bash scripts/lab6.sh test\nbash scripts/lab6.sh check --with-failover', 'bash scripts/lab6.sh all\nbash scripts/lab6.sh check --with-failover');
    body = body.replace('# Остановить только отдельный Lab6, сохранив данные:', `${fence}\n\n### Необязательная проверка сохранности\n\nЭтот блок временно останавливает все узлы Lab6. Выполняйте его после остальных демонстраций. Данные и тома сохраняются.\n\n${fence}bash\n# Остановить только отдельный Lab6, сохранив данные:`);
  }
  const rendered = renderMarkdown(body, metadata[index]);
  let extra = '';
  if (index === 1) extra = callout('Две оболочки', 'Команды **WSL · Bash** вводите в Ubuntu. Блоки **mongosh** — в оболочке, открытой через `shell` на текущем PRIMARY. Из mongosh вернитесь в Bash командой `exit` или Ctrl+D; затем выполняйте следующий Bash-блок.');
  if (index === 3) extra = callout('Одинаковые условия', '`benchmark` каждый раз исследует **оба** запроса: три прогрева, пять измерений до/после. Скрипт удаляет только собственный индекс Lab6 и сохраняет бизнес-индексы Lab5. Если запуск уже выполнен на шаге 3, можно сразу открыть его планы.');
  if (index === 7) extra = callout('После уборки', 'Сценарий проверяет согласованность **до** удаления временных документов. После завершения показывайте `transactions.json` и assertions в коде; пустые временные коллекции — ожидаемый результат cleanup.');
  if (index === 12) extra = callout('Отдельный отказ', 'Следующая команда намеренно останавливает текущий PRIMARY **только Lab6**. Аргумент `--yes` явно подтверждает эксперимент. Сначала убедитесь, что `status` показывает все три здоровых узла.', 'warn');
  return {...metadata[index], html:extra + rendered.html, criterion:rendered.criterion};
});

const decimal = value => Number(value).toFixed(3);
const stamp = checks?.timestamp?.$date ?? checks?.timestamp;
const snapshotDate = stamp ? new Intl.DateTimeFormat('ru-RU', {dateStyle:'long',timeStyle:'short',timeZone:'Asia/Novosibirsk'}).format(new Date(stamp)) : 'отчёт пока отсутствует';
let resultHTML = '<p>Ниже встроен снимок <strong>сохранённых</strong> артефактов проекта. Он не обновляется при открытии HTML и не заменяет новый запуск команд.</p>';
resultHTML += `<div class="snapshot-label">Последняя сохранённая приёмка: ${escape(snapshotDate)} · Новосибирск</div>`;
if (bench) {
  resultHTML += '<h3>Запросы: реальные медианные значения</h3>' + table(
    ['Запрос','Фаза','Время, ms','Docs examined','Keys examined','nReturned'],
    bench.summary.map(row => [row.query, row.phase === 'before' ? 'До' : 'После', row.executionTimeMillis, row.totalDocsExamined, row.totalKeysExamined, row.nReturned]));
  const plans = bench.queries.map(query => {
    const before = bench.rows.find(row => row.query === query.id && row.phase === 'before');
    const after = bench.rows.find(row => row.query === query.id && row.phase === 'after');
    return `**${query.id}**: ${before.stages.replaceAll('|',' / ')} → ${after.stages.replaceAll('|',' / ')}.`;
  }).join(' ');
  resultHTML += callout('Фактические стадии', plans + ' Предполагать COLLSCAN по умолчанию нельзя; показывайте winning plan из сохранённого explain.');
}
if (write) {
  resultHTML += '<h3>Запись и размер индексов: тот же набор документов</h3>' + table(
    ['Фаза','INSERT, ms','INSERT, docs/s','UPDATE, ms','UPDATE, docs/s','Индексы, bytes'],
    write.summary.map(row => [row.phase === 'before' ? 'Базовые индексы' : 'Дополнительный индекс',decimal(row.insertMillis),decimal(row.insertDocsPerSecond),decimal(row.updateMillis),decimal(row.updateDocsPerSecond),row.indexBytes]));
  resultHTML += '<p class="theory">Индекс требует обслуживания при записи. Конкретное время зависит от кеша, checkpoint и фоновой нагрузки; стабильное замедление не гарантируется. Размеры — выделенные страницы WiredTiger и могут сохранять high-water allocation после удаления документов.</p>';
}
resultHTML += '<h3>Сохранённые подтверждения сценариев</h3>' + table(['Сценарий','Проверяемый результат'],[
  ['Seed',seed ? `${seed.pages} страниц; ${seed.feedback} отзывов; seed ${seed.seed}` : 'Запустить seed'],
  ['Bulk API',bulk ? `${bulk.partial.inserted} вставок; ${bulk.partial.modified} изменений; ${bulk.partial.failed} ожидаемые ошибки; replay без дубликатов` : 'Запустить bulk'],
  ['Транзакции',tx?.passed ? 'COMMIT, ROLLBACK, оба error labels, потерянный commit-ответ и replay прошли' : 'Запустить transaction'],
  ['Failover',failover?.passed ? `${failover.before} → ${failover.after}; прежний лидер ${failover.returnedState}; чтение и запись тем же клиентом восстановлены` : 'Отдельно запустить failover --yes'],
  ['Итоговый check',checks?.passed ? `PASS; проверка failover: ${checks.withFailover ? 'включена' : 'не включена'}` : 'Запустить check']
]);
resultHTML += '<h3>Что открыть преподавателю</h3>' + table(['Путь в проекте','Назначение'],[
  ['`artifacts/lab6/plans/`','20 полных JSON explain, включая winning и rejected plans'],
  ['`artifacts/lab6/benchmark/measurements.csv`','Все пять повторов каждой фазы и четыре метрики'],
  ['`artifacts/lab6/benchmark/medians.csv`','Медианные значения до и после'],
  ['`artifacts/lab6/bulk.json`','Частичный успех 1000/1002 и идемпотентный replay'],
  ['`artifacts/lab6/transactions.json`','COMMIT, ROLLBACK и журнал retries'],
  ['`artifacts/lab6/index-write/`','CSV, Markdown и 10 полных collStats'],
  ['`artifacts/lab6/failover.json`','Новый PRIMARY, write/read recovery и catch-up'],
  ['`artifacts/lab6/unit-tests.tap`','10 unit-тестов и нулевое число failures'],
  ['`artifacts/lab6/checks.json`','Семантический итог последнего запуска'],
  ['`docs/lab6/validation.md`','Протокол, ограничения проверки и список исходных файлов']
]);
resultHTML += command('ls -lh artifacts/lab6/benchmark/ artifacts/lab6/index-write/\ncat artifacts/lab6/checks.json\ncat artifacts/lab6/unit-tests.tap', 'bash', 'Открыть материалы приёмки в WSL');
sections.push({title:'Реальные результаты и материалы сдачи',sub:'Снимок измерений из artifacts/lab6, а не вымышленные ожидаемые числа',tags:['артефакты','CSV','защита'],
  files:[['docs/lab6/validation.md','Фактическая приёмка и ограничения'],['artifacts/lab6/benchmark/results.json','Сырые измерения и связь с SHA256 seed']], html:resultHTML,
  criterion:'Вы показали реальные планы, сырые CSV, медианы и подтверждения сценариев; отделили сохранённый снимок от нового запуска.'});

let troubleshooting = table(['Симптом','Причина и действие'],[
  ['`docker: command not found` или недоступен Server','Работайте в Ubuntu WSL с установленным Docker Engine/Compose; сначала проверьте `docker version`.'],
  ['`Run bash scripts/lab6.sh init first`','Подготовьте отдельные секреты командой `bash scripts/lab6.sh init`, затем `up`.'],
  ['`ENOTFOUND mongo2` у хостового клиента','Основной сценарий работает через runner и Compose DNS. Для прямого WSL-клиента нужны все три имени в `/etc/hosts`, совпадающие с rs.conf().'],
  ['`Authentication failed`','Используйте прежние credentials соответствующего volume. Не генерируйте новый пароль наугад и не удаляйте тома.'],
  ['Отсутствует `pg_events.json`','В настроенной Lab5 выполните `bash scripts/lab5.sh sync`. В основной сценарий Lab6 PostgreSQL-записи не входят.'],
  ['`check` сообщает о старом seed или нет медиан','Выполните `seed`, `benchmark`, `bulk`, `transaction`, `index-write` либо весь `all`. После смены seed измерения нужно повторить.'],
  ['`status` ждёт остановленный узел','Он требует все три здоровых состояния. Для аварийной диагностики откройте shell выжившего узла и выполните replSetGetStatus.'],
  ['`NotWritablePrimary` в ручной демонстрации','Снова найдите PRIMARY через status и откройте shell этого сервиса; имя mongo1 не закреплено за лидером.'],
  ['`Another Lab6 command is running`','Завершите текущий сценарий. flock сериализует изменения индексов, fixtures и failpoints.'],
  ['`check --with-failover` не находит отчёт','Сначала отдельно выполните `failover --yes`. Обычный `all` намеренно не останавливает PRIMARY.'],
  ['Временные tx/bulk-документы после теста не найдены','Это ожидаемый cleanup. Смотрите assertions и JSON-отчёты; counts временных ID должны быть нулевыми.'],
  ['Информация в HTML отличается от свежего CSV','Откройте текущий artifacts-файл; HTML содержит снимок момента сборки. После новых измерений пересоберите инструкцию.']
]);
troubleshooting += command('export TICKET_SECRETS_DIR="${TICKET_SECRETS_DIR:-$HOME/.local/share/ticket-platform-ha}"\ndocker compose -f docker-compose.lab6.yml ps -a\ndocker compose -f docker-compose.lab6.yml logs --tail 100 mongo1 mongo2 mongo3\n# Выберите доступный узел из ps, например:\nbash scripts/lab6.sh shell mongo2','bash','Диагностика без удаления данных');
troubleshooting += command("db.hello()\ndb.getSiblingDB('admin').runCommand({replSetGetStatus:1})\n// На текущем PRIMARY, если fault-injection был прерван:\ndb.getSiblingDB('admin').runCommand({configureFailPoint:'failCommand',mode:'off'})",'javascript','Проверить состояния и отключить оставшийся failpoint');
troubleshooting += callout('Сохранить данные', 'Не применяйте `down -v`, `docker volume rm`, `dropDatabase` или force reconfig для исправления обычного сбоя. `down` в управляющем скрипте сохраняет тома. При потере 2/3 голосующих узлов сначала восстановите большинство.', 'warn');
troubleshooting += '<h3>Короткий маршрут полной демонстрации</h3>' + command('cd /mnt/c/TomeD/VSCode/Proga/Afisha/poster\nbash scripts/lab6.sh init\nbash scripts/lab6.sh all\n# Отдельный отказ лидера, после основных проверок:\nbash scripts/lab6.sh failover --yes\nbash scripts/lab6.sh check --with-failover','bash','Все обязательные сценарии в правильном порядке');
troubleshooting += '<p>При наличии Node.js ≥22 на хосте инструкция пересобирается командой <code>node scripts/lab6/build-guide.mjs</code>. Рабочие команды и измерения остаются в проекте; сам HTML можно открыть и использовать без сети.</p>';
sections.push({title:'Типичные ошибки и быстрые решения',sub:'Найти причину по логам, восстановить узел и повторить нужную проверку',tags:['диагностика','runbook'],
  files:[['docs/lab6/failover-runbook.md','Порядок восстановления и диагностики'],['scripts/lab6/build-guide.mjs','Пересборка автономной инструкции']],html:troubleshooting,
  criterion:'Вы знаете, где смотреть причину отказа, как восстановить кластер и какие материалы показывать на защите.'});

const count = sections.length;
const nav = sections.map((section,index) => `<a href="#step-${index+1}" class="navitem" data-title="${escape(section.title.toLocaleLowerCase('ru'))}"><span class="navnum">${String(index+1).padStart(2,'0')}</span><span>${escape(section.title)}</span><span class="navdot" aria-hidden="true"></span></a>`).join('\n');
const cards = sections.map((section,index) => `<section id="step-${index+1}" class="section" data-step="${index+1}">
<div class="stephead"><div class="stepindex">ШАГ ${String(index+1).padStart(2,'0')} / ${count}</div><div class="taglist">${section.tags.map(tag=>`<span${section.dangerous?' class="disruptive"':''}>${escape(tag)}</span>`).join('')}</div></div>
<h2>${escape(section.title)}</h2><p class="sub">${escape(section.sub)}</p>
${section.html}
${section.files.map(([file,description])=>`<div class="fileref"><span>Файл проекта</span><code>${escape(file)}</code><span>${escape(description)}</span></div>`).join('\n')}
<label class="checkline"><input type="checkbox" class="stepcheckbox" data-key="step-${index+1}"><span><b>Проверка пройдена:</b> ${inline(section.criterion)}</span></label>
</section>`).join('\n');
const output = `<!doctype html>
<html lang="ru"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="description" content="Пошаговая проверка Спринта №6 Ticket Platform: MongoDB explain, индексы, bulkWrite, транзакции, Replica Set и отказ PRIMARY.">
<title>Спринт 6 — проверка MongoDB | Ticket Platform</title><style>${css}</style></head>
<body><a class="skiplink" href="#content">Перейти к инструкции</a><div class="layout">
<aside class="sidebar"><div class="brand"><span class="brandmark">TP</span><span><b>Ticket Platform</b><small>Sprint 06 · MongoDB / Replica Set</small></span></div>
<button id="mobilemenu" class="mobile-nav-toggle" aria-expanded="false" aria-controls="stepnav" type="button">Этапы</button>
<div class="searchwrap"><input id="search" type="search" placeholder="Поиск по этапам…" autocomplete="off" aria-label="Поиск по этапам и командам"></div>
<div class="sidebarlabel">Маршрут проверки</div><nav id="stepnav" aria-label="Этапы проверки Спринта 6">${nav}</nav>
<div id="noresults" class="noresults" role="status">Разделов не найдено. Очистите поиск или нажмите Esc.</div>
<div class="sidebottom"><small>Отмечайте успешно выполненные шаги</small><div id="progress" class="progressrail" role="progressbar" aria-label="Прогресс проверки" aria-valuemin="0" aria-valuemax="100" aria-valuenow="0"><div id="progressbar"></div></div><div class="progressvalue" id="progressvalue" aria-live="polite">0 из ${count} · 0%</div><button id="resetprogress" class="button" type="button" style="margin-top:12px;padding:6px 9px;background:#1f3a4f;color:#c4e4eb;border-color:#2f5266">Сбросить отметки</button></div></aside>
<div class="main"><header class="hero"><div class="heroin"><div class="eyebrow">Спринт №6 · руководство для проверки и защиты</div>
<h1>Проверка <span>MongoDB</span><br>индексы, транзакции и репликация</h1>
<p class="lead">Пошаговая демонстрация <strong>ticket-platform-sql</strong>: планы explain, массовые операции, атомарная публикация, выборы PRIMARY и восстановление приложения.</p>
<div class="heroactions"><span class="pill"><strong>2</strong> запроса до / после</span><span class="pill"><strong>3</strong> узла Replica Set</span><span class="pill"><strong>${count}</strong> этапов проверки</span><button class="button primary" id="allSteps" type="button">Начать проверку</button><button class="button" id="print" type="button">Печать / PDF</button></div>
<p class="routehint">Блоки <strong>WSL · Bash</strong> выполняйте в Ubuntu; <strong>mongosh</strong> — в Mongo Shell текущего PRIMARY. HTML только показывает и копирует команды. Все материалы доступны без сети.</p>
</div></header><main class="content" id="content"><div class="introgrid">
<div class="intro"><div class="top">Replica Set</div><div class="big">rs0 · 3 узла</div><div class="bottom">Один PRIMARY, два SECONDARY. Порты 27101–27103; отдельные тома и keyfile.</div></div>
<div class="intro"><div class="top">Официальный драйвер</div><div class="big compact">Node.js + mongodb</div><div class="bottom">Bulk API, ClientSession и bounded retry. Основной клиент работает в сети Compose.</div></div>
<div class="intro"><div class="top">Критерий приёмки</div><div class="big">PASS</div><div class="bottom">Assertions, полные планы, сырые CSV и реальные write/read после failover.</div></div></div>
${cards}
<div class="footer">Оформление по образцу инструкции Lab5 · Содержимое: docs/lab6/demo.md и реальные artifacts/lab6 · Секреты не включены<br>Отметки сохраняются только в этом браузере и не заменяют выполнение проверок.</div>
</main></div></div><div class="toast" id="toast" role="status" aria-live="polite"></div><script>${script}</script></body></html>
`;
// Retain the previously documented path and provide the same naming as the Lab5 sample.
for (const name of ['ticket-platform-lab6-demonstration-guide.html','demonstration-guide-lab6.html']) {
  const destination = new URL(name,root);
  await fs.writeFile(destination,output);
  console.log(`Built ${fileURLToPath(destination)} (${count} sections)`);
}
