const database=db.getSiblingDB('ticket_platform_docs');
function rejected(fn,what){
  let error=null;
  try{fn();}catch(e){error=e;}
  if(!error)throw new Error('Expected validation error: '+what);
  if(error.code!==121)throw new Error('Unexpected error instead of document validation error: '+what+'; '+error);
  print('PASS validator: '+what);
}
const common={_id:'lab5-invalid-page',schemaVersion:NumberInt(1),pgEventId:'10',
  headline:'Тестовая страница',status:'published',keywords:['guide'],sections:[]};
try{
 rejected(()=>database.event_pages.insertOne({...common,summary:'Коротко'}),
  'published page needs summary >=10 chars and at least 1 section');
 rejected(()=>database.editorial_collections.insertOne({_id:'lab5-invalid-list',schemaVersion:NumberInt(1),
  title:'Тестовая подборка',kind:'manual',pageSlugs:['a','a']}),
  'duplicate pageSlug in curated list forbidden');
 rejected(()=>database.visitor_feedback.insertOne({_id:'lab5-invalid-feedback',schemaVersion:NumberInt(1),
  pageSlug:'lab5-crud-page',authorAlias:'tester',rating:NumberInt(6),
  body:'Рейтинг выше пяти недопустим.',moderation:'approved'}),
  'rating must be from 1 through 5');
}finally{
 database.event_pages.deleteOne({_id:'lab5-invalid-page'});
 database.editorial_collections.deleteOne({_id:'lab5-invalid-list'});
 database.visitor_feedback.deleteOne({_id:'lab5-invalid-feedback'});
}
// Cross-collection references are NOT foreign keys: check them explicitly.
const pageIds=new Set(database.event_pages.find({},{_id:1}).toArray().map(x=>x._id));
for(const list of database.editorial_collections.find())
  for(const ref of list.pageSlugs)if(!pageIds.has(ref))throw new Error('Broken collection reference: '+ref);
for(const feedback of database.visitor_feedback.find())
  if(!pageIds.has(feedback.pageSlug))throw new Error('Broken feedback reference: '+feedback.pageSlug);
print('PASS: reference integrity checked for M:N and 1:N');
