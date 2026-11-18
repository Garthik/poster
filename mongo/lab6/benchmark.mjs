import {performance} from 'node:perf_hooks';
import {assert, save, read, median, csv, stages, indexNames, integer, dropOwnedIndex, passed, DATABASE} from './lib.mjs';
import {id} from './data.mjs';

export const QUERIES = [
  {id: 'feedback', collection: 'visitor_feedback', filter: {pageSlug: id('seed-page',7), moderation: 'approved'},
    sort: {createdAt: -1, _id: 1}, limit: 100, index: 'lab6_feedback_page_moderation_created_id',
    key: {pageSlug: 1, moderation: 1, createdAt: -1, _id: 1}},
  {id: 'pages', collection: 'event_pages', filter: {status: 'published', 'editor.alias': 'editor-07'},
    sort: {headline: 1, _id: 1}, limit: 100, index: 'lab6_pages_status_editor_headline_id',
    key: {status: 1, 'editor.alias': 1, headline: 1, _id: 1}}
];
export const metricKeys = ['executionTimeMillis','totalDocsExamined','totalKeysExamined','nReturned'];
export function summarize(rows) {
  return QUERIES.flatMap(q => ['before','after'].map(phase => {
    const samples = rows.filter(r => r.query === q.id && r.phase === phase);
    assert(samples.length >= 5, 'At least five repetitions');
    return {query:q.id, phase, runs:samples.length,
      ...Object.fromEntries([...metricKeys,'wallTimeMillis'].map(k => [k,median(samples.map(s => s[k]))]))};
  }));
}
function cursor(db,q) { return db.collection(q.collection).find(q.filter).sort(q.sort).limit(q.limit); }
export async function benchmark(mongo) {
  const db = mongo.db(DATABASE), count = integer('LAB6_RUNS',5,5), seed = await read('seed.json');
  const rows = [], protectedIndexes = {};
  for (const q of QUERIES) {
    const coll = db.collection(q.collection);
    protectedIndexes[q.id] = (await coll.listIndexes().toArray()).filter(i => !i.name.startsWith('lab6_')).map(i => i.name).sort();
    await dropOwnedIndex(coll,q.index);
    let beforeIds;
    try {
      for (const phase of ['before','after']) {
        if (phase === 'after') await coll.createIndex(q.key, {name:q.index});
        // Natural optimizer choice; do not force a hint and do not remove Lab5 indexes.
        for (let warmup = 0; warmup < 3; warmup++) await cursor(db,q).toArray();
        const resultIds = (await cursor(db,q).toArray()).map(d => d._id);
        assert.equal(resultIds.length, q.limit, 'Fixture has enough selective matches');
        if (phase === 'before') beforeIds = resultIds;
        else assert.deepEqual(resultIds,beforeIds,'Identical ordered business result');
        for (let run = 1; run <= count; run++) {
          const start = performance.now();
          const plan = await cursor(db,q).explain('executionStats');
          const wallTimeMillis = performance.now()-start;
          assert.equal(plan.executionStats.executionSuccess,true);
          await save(`plans/${q.id}-${phase}-${run}.json`,plan);
          rows.push({query:q.id,phase,run,...Object.fromEntries(metricKeys.map(k => [k,plan.executionStats[k]])),
            wallTimeMillis,stages:stages(plan).join('|'),indexes:indexNames(plan).join('|')});
          if (phase === 'after') {
            assert(indexNames(plan).includes(q.index), `${q.id}: optimizer uses the Sprint 6 index`);
            assert(!stages(plan).includes('SORT'), `${q.id}: no blocking SORT`);
          }
        }
        console.log(`${q.id} ${phase}: ${rows.at(-1).stages}; indexes=${rows.at(-1).indexes}`);
      }
    } finally {
      // Leave the requested read indexes installed even if an explain/check failed.
      await coll.createIndex(q.key,{name:q.index});
    }
    assert.deepEqual((await coll.listIndexes().toArray()).filter(i => !i.name.startsWith('lab6_')).map(i => i.name).sort(),protectedIndexes[q.id]);
  }
  const summary = summarize(rows);
  await save('benchmark/measurements.csv',csv(rows));
  await save('benchmark/medians.csv',csv(summary));
  await save('benchmark/results.json',{passed:true,seed:seed.sha256,runs:count,warmups:3,queries:QUERIES,rows,summary,protectedIndexes,timestamp:new Date()});
  const notes = QUERIES.map(q => {
    const b=rows.find(r=>r.query===q.id&&r.phase==='before'), a=rows.find(r=>r.query===q.id&&r.phase==='after');
    return `- **${q.id}**: ${b.stages} (${b.indexes || 'no index'}) → ${a.stages} (${a.indexes}). Equality fields precede sort fields; _id breaks ties. Lab5 indexes retained. ` +
      `Median server time: ${summary.find(r=>r.query===q.id&&r.phase==='before').executionTimeMillis} → ${summary.find(r=>r.query===q.id&&r.phase==='after').executionTimeMillis} ms. ` +
      'Low millisecond resolution, cache and scheduling can obscure timing changes; examine documents/keys and SORT as well.';
  });
  await save('benchmark/summary.md',`# Actual query measurements\n\nSeed SHA256: ${seed.sha256}. ${count} samples/phase, 3 warmups. Natural optimizer; no hint. Full documents fetched, limit 100.\n\n`+
    '|Query|Phase|Median ms|Docs|Keys|Returned|\n|---|---|---:|---:|---:|---:|\n'+summary.map(r=>`|${r.query}|${r.phase}|${r.executionTimeMillis}|${r.totalDocsExamined}|${r.totalKeysExamined}|${r.nReturned}|`).join('\n')+'\n\n'+notes.join('\n')+'\n');
  passed('2 indexed business queries; complete plans, raw CSV and recalculated medians');
}
