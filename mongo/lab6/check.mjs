import fs from 'node:fs/promises';
import path from 'node:path';
import {assert,read,save,csv,median,stages,indexNames,ART,passed,DATABASE} from './lib.mjs';
import {QUERIES,summarize,metricKeys} from './benchmark.mjs';
import {clusterStatus} from './cluster.mjs';

async function sameCSV(name,rows) { assert.equal(await fs.readFile(path.join(ART,name),'utf8'),csv(rows),name+' matches measured JSON'); }
export async function verifyArtifacts({withFailover=false}={}) {
  const seed=await read('seed.json'),bench=await read('benchmark/results.json');
  assert(seed.passed && bench.passed); assert.equal(bench.seed,seed.sha256);
  assert(bench.runs>=5 && bench.warmups>=1);
  assert.deepEqual(bench.queries,QUERIES);
  assert.equal(bench.rows.length,QUERIES.length*2*bench.runs);
  for(const q of QUERIES) {
    for(const phase of ['before','after']) {
      const rows=bench.rows.filter(r=>r.query===q.id && r.phase===phase);
      assert.equal(rows.length,bench.runs);
      assert.deepEqual(rows.map(r=>r.run).sort((a,b)=>a-b),Array.from({length:bench.runs},(_,i)=>i+1));
      for(const row of rows) {
        const plan=await read(`plans/${q.id}-${phase}-${row.run}.json`);
        assert.equal(plan.executionStats.executionSuccess,true);
        for(const key of metricKeys) assert.equal(row[key],plan.executionStats[key],key+' matches full explain');
        assert.equal(row.nReturned,q.limit); assert(row.wallTimeMillis>0);
        assert.equal(row.stages,stages(plan).join('|')); assert.equal(row.indexes,indexNames(plan).join('|'));
        if(phase==='after') {
          assert(indexNames(plan).includes(q.index)); assert(!stages(plan).includes('SORT'));
          const b=bench.rows.find(r=>r.query===q.id && r.phase==='before' && r.run===row.run);
          assert(row.totalDocsExamined < b.totalDocsExamined,'Reduced examined documents (timing improvement is not required)');
        } else assert(!indexNames(plan).includes(q.index));
      }
    }
  }
  assert.deepEqual(bench.summary,summarize(bench.rows),'Medians independently recomputed');
  await sameCSV('benchmark/measurements.csv',bench.rows); await sameCSV('benchmark/medians.csv',bench.summary);
  const bulk=await read('bulk.json');
  assert(bulk.passed && bulk.cleaned && bulk.ordered===false);
  assert.deepEqual(bulk.operationTypes,['insertOne','updateOne']);
  assert.equal(bulk.attempted,1002); assert.equal(bulk.partial.successful,1000); assert.equal(bulk.partial.failed,2);
  assert.equal(bulk.partial.inserted,500); assert.equal(bulk.partial.modified,500);
  assert.deepEqual(bulk.partial.failures.map(f=>f.code).sort((a,b)=>a-b),[121,11000]);
  assert.equal(bulk.replay.matched,1000); assert.equal(bulk.replay.modified,0); assert.equal(bulk.replay.upserted,0);
  const tx=await read('transactions.json');
  assert(tx.passed && tx.cleaned && tx.results.rollback.passed && tx.results.payloadCollisionRejected);
  assert.equal(tx.results.commit.value.alreadyApplied,false); assert.equal(tx.results.replay.value.alreadyApplied,true);
  assert(tx.results.TransientTransactionError.attempt>=2);
  assert.equal(tx.results.UnknownTransactionCommitResult.attempt,1);
  assert(tx.results.UnknownTransactionCommitResult.commitAttempts>=2);
  assert.equal(tx.results.lostReply.bodyCalls,1); assert(tx.results.lostReply.commitAttempts>=2);
  for(const [label,scope] of [['TransientTransactionError','transaction'],['UnknownTransactionCommitResult','commit']])
    assert(tx.retries.some(r=>r.label===label && r.scope===scope));
  assert(Object.values(tx.cleanupCounts).every(n=>n===0));
  const write=await read('index-write/results.json');
  assert(write.passed && write.cleaned && write.runs>=5 && write.warmups>=1);
  assert.equal(write.rows.length,write.runs*2);
  for(const phase of ['before','after']) {
    const rows=write.rows.filter(r=>r.phase===phase),summary=write.summary.find(r=>r.phase===phase);
    assert.equal(rows.length,write.runs);
    for(const key of ['insertMillis','insertDocsPerSecond','updateMillis','updateDocsPerSecond','logicalDataBytes','storageBytes','indexBytes','afterUpdateIndexBytes'])
      assert.equal(summary[key],median(rows.map(r=>r[key])));
    for(const row of rows) {
      assert.equal(row.count,write.count); assert(row.insertMillis>0 && row.updateMillis>0);
      assert.equal(row.insertDocsPerSecond,1000*write.count/row.insertMillis);
      assert.equal(row.updateDocsPerSecond,1000*write.count/row.updateMillis);
      const stats=await read(`index-write/stats-${phase}-${row.run}.json`);
      assert.equal(stats.afterInsert.count,write.count);
      assert.equal(stats.afterInsert.size,row.logicalDataBytes); assert.equal(stats.afterInsert.storageSize,row.storageBytes);
      assert.equal(stats.afterInsert.totalIndexSize,row.indexBytes);
      assert.equal(stats.afterInsert.nindexes,phase==='after'?3:2);
    }
  }
  assert.equal(write.summary[0].logicalDataBytes,write.summary[1].logicalDataBytes,'Identical logical data size');
  await sameCSV('index-write/measurements.csv',write.rows); await sameCSV('index-write/medians.csv',write.summary);
  if(withFailover) {
    const fail=await read('failover.json');
    assert(fail.passed && fail.cleaned && fail.sameClient && fail.beforeWriteSurvived && fail.afterWriteRead && fail.returnedNodeHasNewWrite);
    assert.notEqual(fail.before,fail.after); assert.equal(fail.returnedState,'SECONDARY');
    assert(fail.topology.some(t=>t.primary.includes(fail.after)),'Driver topology observed elected primary');
    const restored=fail.restoredStatus.members.find(m=>m.name===fail.before);
    assert.equal(restored.stateStr,'SECONDARY'); assert.equal(restored.health,1);
  }
  return {passed:true,checked:['full explain statistics','natural index usage','raw CSV and medians','bulk partial errors and replay',
    'two-collection commit and rollback','bounded label retries and idempotency','same-data write/storage measurements',
    ...(withFailover?['new primary','same-client write/read recovery','old node data catch-up']:[])],withFailover};
}
export async function check(mongo,options={}) {
  await clusterStatus(mongo);
  const report=await verifyArtifacts(options),db=mongo.db(DATABASE),seed=await read('seed.json'),bench=await read('benchmark/results.json');
  assert.equal(await db.collection('event_pages').countDocuments({_id:/^lab6-seed-page-/}),seed.pages);
  assert.equal(await db.collection('visitor_feedback').countDocuments({_id:/^lab6-seed-feedback-/}),seed.feedback);
  for(const q of QUERIES) {
    const coll=db.collection(q.collection),indexes=await coll.listIndexes().toArray();
    assert(indexes.some(i=>i.name===q.index));
    assert.deepEqual(indexes.filter(i=>!i.name.startsWith('lab6_')).map(i=>i.name).sort(),bench.protectedIndexes[q.id]);
    const plan=await coll.find(q.filter).sort(q.sort).limit(q.limit).explain('executionStats');
    assert(indexNames(plan).includes(q.index),'Live optimizer still uses index');
  }
  for(const [name,filter] of [
    ['visitor_feedback',{_id:/^lab6-(bulk|failover)-/}],['event_pages',{_id:/^lab6-tx-/}],
    ['editorial_collections',{_id:/^lab6-tx-/}],['lab6_publication_operations',{_id:/^lab6-tx-/}],
    ['lab6_write_baseline',{}],['lab6_write_indexed',{}]
  ]) assert.equal(await db.collection(name).countDocuments(filter),0,`${name}: temporary fixtures removed`);
  for(const name of ['event_pages','editorial_collections','visitor_feedback']) {
    const info=(await db.listCollections({name}).toArray())[0];
    assert(info.options.validator.$jsonSchema); assert.equal(info.options.validationLevel,'strict');
  }
  await save('checks.json',{...report,timestamp:new Date()});
  passed('semantic artifact verification and live indexes/fixtures/validators'+(options.withFailover?' including failover':''));
}
