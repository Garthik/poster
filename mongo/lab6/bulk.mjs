import {MongoBulkWriteError} from 'mongodb';
import {assert, save, passed, DATABASE} from './lib.mjs';
import {feedback, id, random, SEED} from './data.mjs';

export async function bulk(mongo) {
  const db = mongo.db(DATABASE), coll = db.collection('visitor_feedback');
  assert(await db.collection('event_pages').findOne({_id:id('seed-page',7)}), 'Run seed first');
  const scope = {_id: /^lab6-bulk-/}, rng = random(SEED);
  const make = (i,prefix) => ({...feedback(i,rng,prefix),pageSlug:id('seed-page',7),moderation:'pending'});
  await coll.deleteMany(scope);
  let report;
  try {
    const existing = Array.from({length:500},(_,i)=>make(i,'bulk-existing'));
    const incoming = Array.from({length:500},(_,i)=>make(i,'bulk-new'));
    await coll.insertMany(existing);
    const operations = [
      ...incoming.map(document => ({insertOne:{document}})),
      {insertOne:{document:{...make(0,'bulk-invalid'),rating:9}}},
      {insertOne:{document:existing[0]}}, // _id already exists: genuine code 11000.
      ...existing.map(document => ({updateOne:{filter:{_id:document._id},update:{$set:{moderation:'approved'}}}}))
    ];
    let partial;
    try { await coll.bulkWrite(operations,{ordered:false}); assert.fail('Expected two partial write errors'); }
    catch (error) {
      assert(error instanceof MongoBulkWriteError, 'Official driver MongoBulkWriteError');
      const failures = error.writeErrors.map(e => ({index:e.index,code:e.code,message:e.errmsg}));
      assert.deepEqual(failures.map(e=>e.code).sort((a,b)=>a-b),[121,11000]);
      assert.deepEqual(failures.map(e=>e.index).sort((a,b)=>a-b),[500,501]);
      assert(!error.result.getWriteConcernError(), 'No unaccounted write concern failure');
      const r=error.result;
      partial={inserted:r.insertedCount,matched:r.matchedCount,modified:r.modifiedCount,
        successful:r.insertedCount+r.matchedCount,failed:failures.length,failures};
      assert.equal(partial.inserted,500); assert.equal(partial.modified,500); assert.equal(partial.successful,1000);
    }
    assert.equal(await coll.countDocuments(scope),1000);
    assert.equal(await coll.countDocuments({_id:/^lab6-bulk-existing-/,moderation:'approved'}),500);
    assert.equal(await coll.countDocuments({_id:/^lab6-bulk-invalid-/}),0);
    // Repeat the accepted import using stable IDs and upserts. No reset in between.
    const replay = [...incoming,...existing.map(d=>({...d,moderation:'approved'}))].map(d=>({
      updateOne:{filter:{_id:d._id},update:{$set:d},upsert:true}
    }));
    const repeated = await coll.bulkWrite(replay,{ordered:false});
    assert.equal(repeated.upsertedCount,0); assert.equal(repeated.modifiedCount,0);
    assert.equal(repeated.matchedCount,1000); assert.equal(await coll.countDocuments(scope),1000);
    report={passed:true,ordered:false,operationTypes:['insertOne','updateOne'],attempted:operations.length,
      partial,replay:{matched:repeated.matchedCount,modified:repeated.modifiedCount,upserted:repeated.upsertedCount},
      reason:'Different documents are independent; unordered execution allows valid writes after rejected inserts.',timestamp:new Date()};
  } finally { await coll.deleteMany(scope); }
  assert.equal(await coll.countDocuments(scope),0);
  await save('bulk.json',{...report,cleaned:true});
  passed('bulkWrite: 500 inserted, 500 modified, 2 expected errors; replay adds no duplicates; fixtures cleaned');
}
