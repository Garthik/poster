// Run inside the Sprint 7 mongos container via scripts/lab7.sh.
const fs = require('fs');
const check = require('node:assert/strict');
const conn = new Mongo('mongodb://127.0.0.1:27017/?serverSelectionTimeoutMS=60000');
const admin = conn.getDB('admin');
const password = fs.readFileSync('/lab-password', 'utf8').trim();
admin.auth('lab7_admin', password);
check.equal(admin.hello().msg, 'isdbgrid');
const dbName = 'ticket_platform_docs';
db = conn.getDB(dbName);
const meta = conn.getDB('config');
const N = 65536, P = 1024;
const sourceName = 'visitor_feedback', rangedName = 'feedback_ranged';
const reportName = 'page_feedback_report', queueName = 'report_dirty';
const layout = process.env.LAB7_LAYOUT, action = process.env.LAB7_ACTION;
const pipeline = name => JSON.parse(fs.readFileSync('/work/lab7/pipelines/' + name + '.json', 'utf8'));
function sameValues(actual, expected) {
  // Normalize BSON values coming from mongosh and Node's separate JS realms.
  check.deepEqual(JSON.parse(EJSON.stringify(actual)), JSON.parse(EJSON.stringify(expected)));
}
function save(name, value) {
  const path = '/evidence/' + name + '.json';
  fs.writeFileSync(path + '.tmp', EJSON.stringify(value, null, 2, {relaxed:true}) + '\n');
  fs.renameSync(path + '.tmp', path);
}
function command(database, request) {
  const response = database.runCommand(request);
  check.equal(response.ok, 1, response.errmsg);
  return response;
}
const fixturePageSlug = i => 's7-page-' + String(i).padStart(4, '0');
function randomBits(i) {
  let n = Math.imul(i ^ (i >>> 16), 0x45d9f3b);
  n = Math.imul(n ^ (n >>> 16), 0x45d9f3b);
  return (n ^ (n >>> 16)) >>> 0;
}
const events = JSON.parse(fs.readFileSync('/work/events.json', 'utf8'));
check(events.length > 0 && events.every(e => /^\d+$/.test(String(e.pgEventId))));
function page(i) {
  const event = events[i % events.length];
  return {_id:fixturePageSlug(i), schemaVersion:1, pgEventId:String(event.pgEventId),
    headline:'Гид по мероприятию ' + String(i).padStart(4,'0'), status:i % 4 === 0 ? 'draft' : 'published',
    summary:'Рекомендации редакции для посетителей мероприятия.', keywords:['афиша','гид'],
    sections:[{heading:'Перед посещением', body:'Сверьте дату мероприятия и время начала в афише.'}]};
}
function review(i) {
  const bucket = randomBits(i+9817) % 20;
  return {_id:'s7-feedback-'+String(i).padStart(6,'0'), schemaVersion:1,
    pageSlug:fixturePageSlug(randomBits(i+317) % (i % 5 === 0 ? 16 : P)),
    authorAlias:'reader-'+(i%800), rating:1+(randomBits(i+63)%5),
    body:'Отзыв посетителя о полноте редакционного гида.',
    moderation:bucket<14 ? 'approved' : bucket<18 ? 'pending' : 'rejected',
    createdAt:new Date(Date.UTC(2026,8,1) + i*15000)};
}
function chunks(collection) {
  const entry = meta.collections.findOne({_id:dbName+'.'+collection});
  return meta.chunks.find({uuid:entry.uuid}, {_id:0, min:1, max:1, shard:1}).sort({min:1}).toArray();
}
function prepare() {
  command(admin, {enableSharding:dbName, primaryShard:'shardA'});
  load('/work/schema.js');
  for (const [name, method] of [[sourceName,'hashed'],[rangedName,1]]) {
    const key={pageSlug:method}, ns=dbName+'.'+name;
    db.getCollection(name).createIndex(key);
    const existing=meta.collections.findOne({_id:ns});
    if (!existing) {
      const request={shardCollection:ns, key};
      if (method==='hashed') request.numInitialChunks=8;
      command(admin,request);
    } else sameValues(existing.key, key);
    const ranges=chunks(name);
    if (method===1) {
      const middle={pageSlug:fixturePageSlug(P/2)};
      if (!ranges.some(c=>c.min.pageSlug===middle.pageSlug)) command(admin,{split:ns,middle});
      const upper=chunks(name).find(c=>c.min.pageSlug===middle.pageSlug);
      if (upper.shard!=='shardB') command(admin,{moveChunk:ns,find:middle,to:'shardB',_waitForDelete:true});
    }
  }
  for (const name of [reportName,queueName]) {
    if (!db.getCollectionNames().includes(name)) db.createCollection(name);
  }
}
function seed(collection,total,makeDoc) {
  const coll=db.getCollection(collection);
  const initial=coll.countDocuments({});
  if (initial===total) return;
  for(let start=0;start<total;start+=1000) {
    let batch=[];
    for(let i=start;i<Math.min(start+1000,total);i++) batch.push(makeDoc(i));
    if (initial>0) {
      const found=new Set(coll.find({_id:{$in:batch.map(d=>d._id)}},{_id:1}).toArray().map(d=>d._id));
      batch=batch.filter(d=>!found.has(d._id));
    }
    if(batch.length) coll.insertMany(batch,{ordered:false});
  }
  check.equal(coll.countDocuments({}),total);
}
function materialize(slugs=null,target=reportName) {
  const stages=pipeline('page-feedback-merge');
  stages[stages.length-1].$merge.into=target;
  if(slugs) stages.unshift({$match:{_id:{$in:slugs}}});
  db.event_pages.aggregate(stages,{allowDiskUse:true,writeConcern:{w:'majority'}}).toArray();
}
function rebuild() {
  const stage=reportName+'_build';
  if(db.getCollectionNames().includes(stage)) db.getCollection(stage).drop();
  db.createCollection(stage);
  materialize(null,stage);
  command(admin,{renameCollection:dbName+'.'+stage,to:dbName+'.'+reportName,dropTarget:true});
  return db.getCollection(reportName).countDocuments({});
}
// The source document and the affected group tokens commit together. A new token
// for every edit makes a conditional acknowledgement safe even across delete/reinsert.
function applyChange(id,document,collection=sourceName) {
  check.equal(typeof id,'string');
  check([sourceName,'event_pages'].includes(collection),'Unsupported source collection');
  if(document!==null) check.equal(document._id,id);
  const session=conn.startSession();
  try {
    session.withTransaction(()=>{
      const tx=session.getDatabase(dbName);
      const source=tx.getCollection(collection);
      let touched;
      if(collection==='event_pages') {
        if(document) source.replaceOne({_id:id},document,{upsert:true});
        else source.deleteOne({_id:id});
        touched=[id];
      } else {
        const old=source.findOne({_id:id});
        if(document) check(tx.event_pages.findOne({_id:document.pageSlug},{_id:1}),'Unknown page');
        if(old) {
          const sourceKey={_id:id,pageSlug:old.pageSlug};
          if(document) source.replaceOne(sourceKey,document);
          else source.deleteOne(sourceKey);
        } else if(document) source.insertOne(document);
        touched=[...new Set([old?.pageSlug,document?.pageSlug].filter(Boolean))];
      }
      for(const group of touched) tx.getCollection(queueName).updateOne({_id:group},
        {$set:{token:new ObjectId()},$setOnInsert:{since:new Date()}},{upsert:true});
    },{readConcern:{level:'snapshot'},writeConcern:{w:'majority'},readPreference:'primary'});
  } finally {session.endSession();}
}
function refresh(acknowledge=true) {
  const queue=db.getCollection(queueName), seen=queue.find().sort({_id:1}).toArray();
  for(let i=0;i<seen.length;i+=128) {
    const batch=seen.slice(i,i+128), slugs=batch.map(d=>d._id);
    materialize(slugs);
    const live=new Set(db.event_pages.find({_id:{$in:slugs}},{_id:1}).toArray().map(d=>d._id));
    const removed=slugs.filter(s=>!live.has(s));
    if(removed.length) db.getCollection(reportName).deleteMany({_id:{$in:removed}});
    if(acknowledge) queue.bulkWrite(batch.map(d=>({deleteOne:{filter:{_id:d._id,token:d.token}}})),
      {ordered:false,writeConcern:{w:'majority'}});
  }
  return seen.map(d=>d._id);
}
function verifyReport() {
  const raw=db.getCollection(sourceName).aggregate([
    {$match:{moderation:'approved'}},{$group:{_id:'$pageSlug',n:{$sum:1},points:{$sum:'$rating'}}}
  ]).toArray();
  const byPage=new Map(raw.map(x=>[x._id,x]));
  const pages=db.event_pages.find({},{_id:1}).sort({_id:1}).toArray();
  const rows=db.getCollection(reportName).find().sort({_id:1}).toArray();
  check.equal(rows.length,pages.length);
  for(const [i,row] of rows.entries()) {
    const ref=byPage.get(row._id) || {n:0,points:0};
    check.equal(row._id,pages[i]._id);
    check.equal(row.reviews, ref.n); check.equal(row.ratingSum,ref.points);
    if(ref.n) check(Math.abs(row.averageRating-ref.points/ref.n)<0.005001);
    else check.equal(row.averageRating,null);
  }
  return {pages:rows.length,approved:raw.reduce((s,r)=>s+r.n,0),checkedRows:rows.length};
}
function reports() {
  const top=db.getCollection(sourceName).aggregate(pipeline('published-feedback'),{allowDiskUse:true}).toArray();
  const facet=db.getCollection(sourceName).aggregate(pipeline('moderation')).toArray()[0];
  const verified=verifyReport();
  const published=db.event_pages.find({status:'published'},{_id:1}).toArray().map(p=>p._id);
  const first=db.getCollection(reportName).find({_id:{$in:published},reviews:{$gt:0}}).sort({reviews:-1,_id:1}).limit(10).toArray();
  sameValues(top.map(x=>[x._id,x.reviews,x.averageRating]), first.map(x=>[x._id,x.reviews,x.averageRating]));
  check.equal(facet.byStatus.reduce((s,r)=>s+r.count,0),db.getCollection(sourceName).countDocuments({}));
  check.equal(facet.approvedRatings.reduce((s,r)=>s+r.count,0),verified.approved);
  const value={top,facet,materialized:db.getCollection(reportName).find({_id:{$in:[top[0]._id,fixturePageSlug(P)]}}).sort({_id:1}).toArray(),verified};
  save('reports',value);
  const pageProjection={_id:1,headline:1,summary:1,sections:1,keywords:1};
  const publicPage=db.event_pages.findOne({_id:top[0]._id,status:'published'},pageProjection);
  const days=pipeline('daily-ranking');
  const ranking=db.getCollection(sourceName).aggregate(days).toArray();
  const [lower,upper]=days[0].$match.$expr.$and;
  const start=new Date(lower.$gte[1].$toDate), end=new Date(upper.$lt[1].$toDate);
  const day=start.toISOString().slice(0,10);
  const approvedOnDay={moderation:'approved',createdAt:{$gte:start,$lt:end}};
  check.equal(ranking.reduce((s,m)=>s+m.score,0),db.getCollection(sourceName).countDocuments(approvedOnDay));
  save('redis-source',{publicPage,day,ranking});
  return verified;
}
function incrementalDemo() {
  const id='s7-inc-probe', a=fixturePageSlug(7), b=fixturePageSlug(P);
  const pageId='s7-inc-new-page';
  const coll=db.getCollection(reportName);
  const get=key=>coll.findOne({_id:key});
  const initial=get(a);
  check.equal(get(b).reviews,0);
  const example={...review(7), _id:id,pageSlug:a,moderation:'pending',rating:5};
  const evidence=[];
  function expect(step, changed, expectedGroups, n, points, otherN, otherSum) {
    sameValues([...changed].sort(),[...expectedGroups].sort());
    const aa=get(a), bb=get(b);
    sameValues([aa.reviews,aa.ratingSum,bb.reviews,bb.ratingSum],[n,points,otherN,otherSum]);
    evidence.push({step,refreshed:changed,a:aa,b:bb});
  }
  try {
    applyChange(id,example);
    expect('insert-pending',refresh(),[a],initial.reviews,initial.ratingSum,0,0);
    applyChange(id,{...example,moderation:'approved'});
    expect('approve-before-ack',refresh(false),[a],initial.reviews+1,initial.ratingSum+5,0,0);
    expect('replay-after-interruption',refresh(),[a],initial.reviews+1,initial.ratingSum+5,0,0);
    applyChange(id,{...example,moderation:'approved',rating:2});
    expect('edit-rating',refresh(),[a],initial.reviews+1,initial.ratingSum+2,0,0);
    applyChange(id,{...example,pageSlug:b,moderation:'approved',rating:2});
    expect('move-to-other-page',refresh(),[a,b],initial.reviews,initial.ratingSum,1,2);
    applyChange(id,null);
    expect('delete-last-approved',refresh(),[b],initial.reviews,initial.ratingSum,0,0);
    expect('empty-queue',refresh(),[],initial.reviews,initial.ratingSum,0,0);
    check.equal(get(b).averageRating,null);
  } finally { applyChange(id,null); refresh(); }
  let newPage;
  try {
    applyChange(pageId,{...page(P),_id:pageId},'event_pages');
    sameValues(refresh(),[pageId]);
    newPage=get(pageId);
    sameValues(newPage,{_id:pageId,reviews:0,ratingSum:0,averageRating:null});
  } finally { applyChange(pageId,null,'event_pages'); refresh(); }
  check.equal(get(pageId),null);
  const before=db.getCollection(reportName).find().sort({_id:1}).toArray();
  rebuild();
  const after=db.getCollection(reportName).find().sort({_id:1}).toArray();
  sameValues(after,before);
  save('incremental',{initial,steps:evidence,pageLifecycle:{created:newPage,afterDelete:get(pageId)},
    fullEqualsIncremental:true,verified:verifyReport()});
}
function distribution(collection) {
  const actual=db.getCollection(collection).aggregate([
    {$collStats:{storageStats:{scale:1}}},{$project:{_id:0,shard:1,documents:'$storageStats.count'}},{$sort:{shard:1}}
  ]).toArray();
  check.equal(actual.length,2);
  check(actual.every(x=>x.documents>0));
  check.equal(actual.reduce((s,x)=>s+x.documents,0),N);
  // Preserve all 64 bits of hashed boundaries in the human-readable JSON evidence.
  const exact=chunks(collection).map(c=>({shard:c.shard,min:EJSON.serialize(c.min,{relaxed:false}),
    max:EJSON.serialize(c.max,{relaxed:false})}));
  return {documents:actual,chunks:exact};
}
function routed(label,collection,filter) {
  const plan=db.getCollection(collection).find(filter).explain('executionStats');
  const stats=plan.executionStats;
  const shards=stats.executionStages.shards.map(s=>({name:s.shardName,nReturned:s.nReturned})).sort((a,b)=>a.name.localeCompare(b.name));
  save('explain-'+label,plan);
  return {collection,filter,shards,nReturned:stats.nReturned,docsExamined:stats.totalDocsExamined,keysExamined:stats.totalKeysExamined};
}
function routes() {
  const doc=review(7);
  const equal={pageSlug:doc.pageSlug,_id:doc._id}, without={_id:doc._id};
  const range={pageSlug:{$gte:fixturePageSlug(0),$lt:fixturePageSlug(16)}};
  const requests={};
  for(const [tag,collection] of [['hashed',sourceName],['ranged',rangedName]]) {
    for(const [key,filter] of [['targeted',equal],['scatter',without],['range',range]]) {
      const r=routed(tag+'-'+key,collection,filter);
      check.equal(r.shards.length,key==='targeted' || (key==='range' && tag==='ranged') ? 1 : 2);
      if(key!=='range') check.equal(r.nReturned,1);
      requests[tag+'-'+key]=r;
    }
  }
  check.equal(requests['hashed-range'].nReturned,requests['ranged-range'].nReturned);
  sameValues(db.getCollection(sourceName).findOne(equal),db.getCollection(sourceName).findOne(without));
  const candidates={};
  for(const field of ['pageSlug','createdAt','moderation']) {
    const aggregate=db.getCollection(sourceName).aggregate([
      {$group:{_id:'$'+field,n:{$sum:1}}},
      {$group:{_id:null,distinct:{$sum:1},largest:{$max:'$n'},total:{$sum:'$n'}}},{$unset:'_id'}
    ],{allowDiskUse:true}).toArray()[0];
    check.equal(aggregate.total,N);
    candidates[field]=aggregate;
  }
  const value={version:admin.version(),layout,at:new Date(),shards:command(admin,{listShards:1}).shards.map(s=>({name:s._id,host:s.host})),
    count:N,hashed:distribution(sourceName),ranged:distribution(rangedName),requests,candidates};
  save('routing',value);
  return value.shards;
}
if(action==='demo') {
  prepare();
  // Recover test records from a previously interrupted demonstration.
  applyChange('s7-inc-probe',null);
  applyChange('s7-inc-new-page',null,'event_pages');
  seed('event_pages',P+1,page);
  for(const collection of [sourceName,rangedName]) seed(collection,N,review);
  print('Fixture ready: '+N+' feedback documents per shard-key experiment.');
  rebuild(); refresh();
  const verified=reports(); const shards=routes(); incrementalDemo();
  save('run',{passed:true,layout,version:admin.version(),at:new Date(),verified,shards});
  print('PASS: reports, routing on both shards, incremental and full rebuild ('+layout+').');
} else if(action==='apply') {
  const change=EJSON.parse(fs.readFileSync(0,'utf8'));
  check(Object.hasOwn(change,'document'));
  applyChange(change.id,change.document,change.collection);
  print('Source change and refresh tokens committed.');
} else if(action==='refresh') printjson({refreshed:refresh()});
else if(action==='rebuild') printjson({rows:rebuild(),refreshed:refresh()});
else if(action==='reports') printjson(reports());
else throw Error('Unknown action '+action);
