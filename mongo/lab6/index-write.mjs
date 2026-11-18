import {performance} from 'node:perf_hooks';
import {createHash} from 'node:crypto';
import {assert, integer, save, csv, median, dropOwnedIndex, passed, DATABASE} from './lib.mjs';
import {feedback, random, SEED} from './data.mjs';
import {QUERIES} from './benchmark.mjs';

export async function indexWrite(mongo) {
  const db=mongo.db(DATABASE),count=integer('LAB6_WRITE_COUNT',6000,1000),runs=integer('LAB6_RUNS',5,5);
  const source=(await db.listCollections({name:'visitor_feedback'}).toArray())[0];
  assert(source?.options.validator,'Lab5 schema must be installed');
  const rng=random(SEED),docs=Array.from({length:count},(_,i)=>feedback(i,rng,'write-feedback'));
  const sha256=createHash('sha256').update(JSON.stringify(docs)).digest('hex');
  const collections={before:db.collection('lab6_write_baseline'),after:db.collection('lab6_write_indexed')};
  const index=QUERIES[0],rows=[];
  for(const [phase,coll] of Object.entries(collections)) {
    if(!(await db.listCollections({name:coll.collectionName}).toArray()).length)
      await db.createCollection(coll.collectionName,{validator:source.options.validator,validationLevel:'strict',validationAction:'error'});
    assert.equal(await coll.countDocuments({_id:{$not:/^lab6-write-feedback-/}}),0,'Dedicated experiment collection contains only owned fixtures');
    await coll.deleteMany({_id:/^lab6-write-feedback-/});
    await coll.createIndex({pageSlug:1,moderation:1}); // Same Lab5 baseline for both phases.
    await dropOwnedIndex(coll,index.index);
    if(phase==='after') await coll.createIndex(index.key,{name:index.index});
  }
  async function trial(phase,run,warmup=false) {
    const coll=collections[phase];
    assert.equal(await coll.countDocuments({}),0,'Equal empty starting fixture');
    try {
      let start=performance.now();
      const inserted=await coll.insertMany(docs,{ordered:false});
      const insertMillis=performance.now()-start;
      assert.equal(inserted.insertedCount,count);
      const afterInsert=await db.command({collStats:coll.collectionName,scale:1});
      start=performance.now();
      const changed=await coll.updateMany({_id:/^lab6-write-feedback-/},{$set:{createdAt:new Date('2030-01-01T00:00:00Z')}});
      const updateMillis=performance.now()-start;
      assert.equal(changed.modifiedCount,count);
      assert.equal(await coll.countDocuments({createdAt:new Date('2030-01-01T00:00:00Z')}),count);
      const afterUpdate=await db.command({collStats:coll.collectionName,scale:1});
      if(!warmup) {
        await save(`index-write/stats-${phase}-${run}.json`,{afterInsert,afterUpdate});
        rows.push({phase,run,count,insertMillis,insertDocsPerSecond:count*1000/insertMillis,
          updateMillis,updateDocsPerSecond:count*1000/updateMillis,
          logicalDataBytes:afterInsert.size,storageBytes:afterInsert.storageSize,
          indexBytes:afterInsert.totalIndexSize,afterUpdateIndexBytes:afterUpdate.totalIndexSize});
      }
    } finally { await coll.deleteMany({_id:/^lab6-write-feedback-/}); }
  }
  try {
    for(const phase of ['before','after']) await trial(phase,0,true);
    for(let run=1;run<=runs;run++) {
      // Alternate order to reduce drift bias, with the same in-memory documents.
      for(const phase of run%2?['before','after']:['after','before']) await trial(phase,run);
    }
  } finally {
    for(const coll of Object.values(collections)) await coll.deleteMany({_id:/^lab6-write-feedback-/});
  }
  const summary=['before','after'].map(phase=>({phase,runs,count,...Object.fromEntries(
    ['insertMillis','insertDocsPerSecond','updateMillis','updateDocsPerSecond','logicalDataBytes','storageBytes','indexBytes','afterUpdateIndexBytes']
      .map(key=>[key,median(rows.filter(r=>r.phase===phase).map(r=>r[key]))]))}));
  await save('index-write/measurements.csv',csv(rows));
  await save('index-write/medians.csv',csv(summary));
  await save('index-write/results.json',{passed:true,sha256,seed:SEED,warmups:1,runs,count,rows,summary,cleaned:true,timestamp:new Date()});
  await save('index-write/summary.md','# Actual index write/storage measurements\n\n'+
    `Identical ${count} documents, SHA256 ${sha256}. ${runs} runs/phase; 1 warmup each. Majority+journal acknowledged. Baseline has _id and Lab5 pageSlug/moderation index; after adds ${index.index}.\n\n`+
    '|Phase|Insert median ms|Insert docs/s|Update median ms|Update docs/s|Index bytes|Storage bytes|\n|---|---:|---:|---:|---:|---:|---:|\n'+
    summary.map(r=>`|${r.phase}|${r.insertMillis.toFixed(3)}|${r.insertDocsPerSecond.toFixed(1)}|${r.updateMillis.toFixed(3)}|${r.updateDocsPerSecond.toFixed(1)}|${r.indexBytes}|${r.storageBytes}|`).join('\n')+
    '\n\nIndexes require maintenance on insertion and on updates of createdAt. Timing direction is not asserted. collStats reports allocated compressed storage and index bytes, which can lag writes/checkpoints and retain high-water allocations. Dedicated persistent collections are emptied, never dropped; allocation is not a per-document cost. Do not infer a universal speed ratio from one host.\n');
  passed('same-data write/update benchmark, alternating order, medians/throughput and complete collStats; fixtures cleaned');
}
