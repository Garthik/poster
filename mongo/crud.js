const database=db.getSiblingDB('ticket_platform_docs');
function check(ok,message){if(!ok)throw new Error(message); print('PASS: '+message);}
const base=database.event_pages.findOne({_id:/^pg-event-/});
if(!base)throw new Error('Run sync before CRUD test');
const pageId='lab5-crud-page', collectionId='lab5-crud-list', feedbackId='lab5-crud-comment';
// Delete remnants of an interrupted earlier run; only reserved demo identifiers.
for(const [coll,id] of [['event_pages',pageId],['editorial_collections',collectionId],['visitor_feedback',feedbackId]])
  database[coll].deleteOne({_id:id});
try{
  // CREATE / READ / UPDATE / DELETE of the main embedded document.
  database.event_pages.insertOne({_id:pageId,schemaVersion:NumberInt(1),pgEventId:base.pgEventId,
    headline:'Черновая страница для проверки CRUD',status:'draft',keywords:['demo'],sections:[]});
  check(!!database.event_pages.findOne({_id:pageId}),'event_pages CREATE + READ');
  database.event_pages.updateOne({_id:pageId},{$set:{status:'published',
    summary:'Подробные рекомендации для тестового посетителя.',
    sections:[{heading:'Маршрут',body:'Маршрут уточняется у администрации площадки.'}]}});
  check(database.event_pages.findOne({_id:pageId}).status==='published','event_pages UPDATE (embedding)');
  // CREATE / READ / UPDATE / DELETE for M:N reference collection.
  database.editorial_collections.insertOne({_id:collectionId,schemaVersion:NumberInt(1),
    title:'Временная подборка',kind:'manual',pageSlugs:[pageId],curator:{alias:'tester'}});
  check(database.editorial_collections.findOne({_id:collectionId}).pageSlugs.includes(pageId),'editorial_collections CREATE + READ');
  database.editorial_collections.updateOne({_id:collectionId},{$addToSet:{pageSlugs:base._id}});
  check(database.editorial_collections.findOne({_id:collectionId}).pageSlugs.length===2,'editorial_collections UPDATE reference');
  // CREATE / READ / UPDATE / DELETE for 1:N feedback references.
  database.visitor_feedback.insertOne({_id:feedbackId,schemaVersion:NumberInt(1),pageSlug:pageId,
    authorAlias:'tester',rating:NumberInt(4),body:'Временный отзыв для CRUD теста.',moderation:'pending'});
  check(database.visitor_feedback.findOne({_id:feedbackId}).rating===4,'visitor_feedback CREATE + READ');
  database.visitor_feedback.updateOne({_id:feedbackId},{$set:{moderation:'approved'}});
  check(database.visitor_feedback.findOne({_id:feedbackId}).moderation==='approved','visitor_feedback UPDATE');
}finally{
  database.visitor_feedback.deleteOne({_id:feedbackId});
  database.editorial_collections.deleteOne({_id:collectionId});
  database.event_pages.deleteOne({_id:pageId});
}
check(!database.event_pages.findOne({_id:pageId}) && !database.editorial_collections.findOne({_id:collectionId})
 && !database.visitor_feedback.findOne({_id:feedbackId}),'DELETE from all 3 collections');
