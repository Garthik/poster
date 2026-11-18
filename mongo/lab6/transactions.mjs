import {MongoError} from 'mongodb';
import {assert, client, save, passed, DATABASE} from './lib.mjs';
import {page, pgEvents, id} from './data.mjs';
import {runTransaction} from './transaction-retry.mjs';

const RECEIPTS='lab6_publication_operations';
export async function publish(mongo,{pageSlug,collectionId,operationId,afterFirstWrite,retryOptions={}}) {
  const db=mongo.db(DATABASE),session=mongo.startSession();
  try {
    return await runTransaction(session,operationId,async s=>{
      const prior=await db.collection(RECEIPTS).findOne({_id:operationId},{session:s});
      if(prior) {
        assert.equal(prior.pageSlug,pageSlug,'Operation ID payload must match');
        assert.equal(prior.collectionId,collectionId,'Operation ID payload must match');
        return {alreadyApplied:true};
      }
      const p=await db.collection('event_pages').findOne({_id:pageSlug},{session:s});
      const c=await db.collection('editorial_collections').findOne({_id:collectionId},{session:s});
      assert(p && c,'Both page and collection must exist');
      assert(p.summary?.length>=10 && p.sections?.length>0,'Published page requires summary and sections');
      assert(c.pageSlugs.includes(pageSlug) || c.pageSlugs.length<20,'Collection capacity is 20');
      const refs=await db.collection('event_pages').countDocuments({_id:{$in:c.pageSlugs}},{session:s});
      assert.equal(refs,c.pageSlugs.length,'No dangling collection references');
      const changed=await db.collection('event_pages').updateOne({_id:pageSlug},{$set:{status:'published'}},{session:s});
      assert.equal(changed.matchedCount,1);
      if(afterFirstWrite) await afterFirstWrite(s);
      const linked=await db.collection('editorial_collections').updateOne({_id:collectionId},{$addToSet:{pageSlugs:pageSlug}},{session:s});
      assert.equal(linked.matchedCount,1);
      await db.collection(RECEIPTS).insertOne({_id:operationId,pageSlug,collectionId},{session:s});
      return {alreadyApplied:false};
    },retryOptions);
  } finally { await session.endSession(); }
}

export async function transactions(mongo) {
  const db=mongo.db(DATABASE),pgEventId=(await pgEvents())[0].pgEventId;
  // Auxiliary collection has MongoDB's unique _id index; no new fields on Lab5 models.
  if(!(await db.listCollections({name:RECEIPTS}).toArray()).length) await db.createCollection(RECEIPTS);
  const pageSlug=id('tx-page',0),collectionId='lab6-tx-collection',anchor=id('seed-page',1);
  assert(await db.collection('event_pages').findOne({_id:anchor}),'Run seed first');
  async function cleanup() {
    await db.collection(RECEIPTS).deleteMany({_id:/^lab6-tx-/});
    await db.collection('editorial_collections').deleteOne({_id:collectionId});
    await db.collection('event_pages').deleteOne({_id:pageSlug});
  }
  async function reset() {
    await cleanup();
    await db.collection('event_pages').insertOne({...page(0,pgEventId,'tx-page'),status:'draft'});
    await db.collection('editorial_collections').insertOne({_id:collectionId,schemaVersion:1,
      title:'Lab6 publication target',kind:'thematic',pageSlugs:[anchor]});
  }
  async function snapshot() {
    return {page:await db.collection('event_pages').findOne({_id:pageSlug}),
      collection:await db.collection('editorial_collections').findOne({_id:collectionId})};
  }
  async function consistent(operationId) {
    const actual=await snapshot();
    assert.equal(actual.page.status,'published');
    assert.equal(actual.collection.pageSlugs.filter(s=>s===pageSlug).length,1);
    assert.equal(await db.collection(RECEIPTS).countDocuments({_id:operationId}),1);
  }
  const results={}, retries=[];
  const args=operationId=>({pageSlug,collectionId,operationId,retryOptions:{onRetry:e=>retries.push(e)}});
  const adminClient=await client('ticket-lab6-fault-controller',true);
  let faultClient;
  const configure=command=>adminClient.db('admin').command(command);
  try {
    await reset();
    results.commit=await publish(mongo,args('lab6-tx-commit'));
    await consistent('lab6-tx-commit');
    results.replay=await publish(mongo,args('lab6-tx-commit'));
    assert.equal(results.replay.value.alreadyApplied,true); await consistent('lab6-tx-commit');
    await assert.rejects(publish(mongo,{...args('lab6-tx-commit'),collectionId:'lab6-other-collection'}),/payload must match/);
    results.payloadCollisionRejected=true;
    await reset();
    const before=await snapshot();
    await assert.rejects(publish(mongo,{...args('lab6-tx-rollback'),afterFirstWrite:async s=>{
      assert.equal((await db.collection('event_pages').findOne({_id:pageSlug},{session:s})).status,'published');
      // In-flight write is invisible outside the transaction.
      assert.equal((await db.collection('event_pages').findOne({_id:pageSlug})).status,'draft');
      throw new Error('Controlled rollback after first collection write');
    }}),/Controlled rollback/);
    assert.deepEqual(await snapshot(),before,'Both collection snapshots unchanged');
    assert.equal(await db.collection(RECEIPTS).countDocuments({_id:'lab6-tx-rollback'}),0);
    results.rollback={passed:true,unchangedCollections:['event_pages','editorial_collections'],receiptAbsent:true};
    for(const label of ['TransientTransactionError','UnknownTransactionCommitResult']) {
      await reset();
      const appName=`ticket-lab6-tx-${label}`;
      faultClient=await client(appName);
      // Real server replies with specified label once; appName isolates other clients.
      await configure({configureFailPoint:'failCommand',mode:{times:1},data:{appName,
        failCommands:[label==='TransientTransactionError'?'update':'commitTransaction'],
        errorCode:label==='TransientTransactionError'?112:1,errorLabels:[label]}});
      try {
        const operationId=`lab6-tx-${label.toLowerCase()}`;
        results[label]=await publish(faultClient,args(operationId));
        await consistent(operationId);
        assert(retries.some(e=>e.label===label),'Application retry observed '+label);
        if(label==='TransientTransactionError') assert.equal(results[label].attempt,2);
        else { assert.equal(results[label].attempt,1); assert.equal(results[label].commitAttempts,2); }
        await publish(faultClient,args(operationId)); await consistent(operationId);
      } finally {
        await configure({configureFailPoint:'failCommand',mode:'off'});
        await faultClient.close(); faultClient=undefined;
      }
    }
    // Commit really succeeds, then the response is deliberately hidden from the caller.
    // This complements the server failpoint by exercising a post-commit lost reply.
    await reset();
    let hideOnce=true,bodyCalls=0;
    const lostArgs=args('lab6-tx-lost-reply');
    lostArgs.afterFirstWrite=async()=>{bodyCalls++;};
    lostArgs.retryOptions.commit=async s=>{
      await s.commitTransaction();
      if(hideOnce) { hideOnce=false; const e=new MongoError('Injected lost successful commit reply'); e.addErrorLabel('UnknownTransactionCommitResult'); throw e; }
    };
    results.lostReply=await publish(mongo,lostArgs);
    assert.equal(bodyCalls,1); await consistent('lab6-tx-lost-reply');
    await publish(mongo,args('lab6-tx-lost-reply')); await consistent('lab6-tx-lost-reply');
    results.lostReply.bodyCalls=bodyCalls;
  } finally {
    if(faultClient) await faultClient.close();
    await adminClient.close();
    await cleanup();
  }
  const counts={page:await db.collection('event_pages').countDocuments({_id:pageSlug}),
    collection:await db.collection('editorial_collections').countDocuments({_id:collectionId}),
    receipts:await db.collection(RECEIPTS).countDocuments({_id:/^lab6-tx-/})};
  assert(Object.values(counts).every(n=>n===0));
  await save('transactions.json',{passed:true,results,retries,cleaned:true,cleanupCounts:counts,
    faultSource:'MongoDB failCommand with appName; additional explicitly injected post-commit lost reply',timestamp:new Date()});
  passed('COMMIT, cross-collection ROLLBACK, server TTE/UnknownCommit labels, lost reply, idempotent receipt replay');
}
