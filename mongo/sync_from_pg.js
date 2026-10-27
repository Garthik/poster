// pg_events.json is produced by PostgreSQL, not a replicated relational model.
const fs = require('fs');
const database = db.getSiblingDB('ticket_platform_docs');
const rows = JSON.parse(fs.readFileSync('/work/artifacts/pg_events.json','utf8'));
if (!Array.isArray(rows) || rows.length < 2) throw new Error('Need at least two PostgreSQL events. Run seed first.');
for (const e of rows) {
  const id = String(e.pgEventId);
  const slug = `pg-event-${id}`;
  const page = {
    pgEventId:id,
    headline:`${e.name} — гид посетителя`,
    summary:`Как подготовиться к мероприятию «${e.name}»: маршрут, вход и полезные советы.`,
    status:'published', keywords:['visit','guide'],
    sections:[
      {heading:'Перед посещением',body:'Приходите заранее, чтобы спокойно пройти проверку билета.'},
      {heading:'Полезная информация',body:'Адрес и время проведения сверяйте с официальной карточкой события.'}
    ],
    editor:{alias:'editorial-team'}
  };
  const existing=database.event_pages.findOne({_id:slug},{schemaVersion:1});
  if(existing && Number(existing.schemaVersion)===2)
    page.readingMinutes=NumberInt(Math.max(1,Math.min(60,Math.ceil(page.summary.length/150))));
  database.event_pages.updateOne({_id:slug},{$set:page,$setOnInsert:{schemaVersion:NumberInt(1)}},{upsert:true});
}
const first=`pg-event-${rows[0].pgEventId}`, second=`pg-event-${rows[1].pgEventId}`;
const third=`pg-event-${rows[rows.length-1].pgEventId}`;
database.editorial_collections.updateOne({_id:'weekend-guides'},{$set:{
  title:'Идеи для выходных',kind:'thematic',
  pageSlugs:[first,second],curator:{alias:'editorial-team'}
},$setOnInsert:{schemaVersion:NumberInt(1)}},{upsert:true});
database.editorial_collections.updateOne({_id:'editors-choice'},{$set:{
  title:'Выбор редакции',kind:'manual',
  pageSlugs:[first,third],curator:{alias:'editorial-team'}
},$setOnInsert:{schemaVersion:NumberInt(1)}},{upsert:true});
for (const [id,pageSlug,rating,body] of [
  ['sample-feedback-1',first,5,'Полезная информация о посещении мероприятия.'],
  ['sample-feedback-2',first,4,'Отличная подборка советов для посетителей.'],
  ['sample-feedback-3',second,5,'Мне понравилась структура страницы и описание.']
]) {
  database.visitor_feedback.updateOne({_id:id},{$set:{pageSlug,
    authorAlias:'sample-reader',rating:NumberInt(rating),body,moderation:'approved',
    createdAt:new Date('2026-10-25T12:00:00Z')},$setOnInsert:{schemaVersion:NumberInt(1)}},{upsert:true});
}
print(`OK: ${rows.length} event pages; 2 curated lists; 3 visitor feedback documents`);
