import {createHash} from 'node:crypto';
import {assert, save, passed, DATABASE} from './lib.mjs';
import {page, feedback, pgEvents, id, random, SEED, PAGE_COUNT, FEEDBACK_COUNT} from './data.mjs';

export async function seed(mongo) {
  const db = mongo.db(DATABASE), events = await pgEvents();
  // Scoped replacement of a reserved fixture namespace, never drop a collection.
  await db.collection('visitor_feedback').deleteMany({_id: /^lab6-seed-feedback-/});
  await db.collection('event_pages').deleteMany({_id: /^lab6-seed-page-/});
  const hash = createHash('sha256'), rng = random(SEED);
  async function fill(name, count, factory) {
    const coll = db.collection(name);
    for (let offset = 0; offset < count; offset += 1000) {
      const docs = Array.from({length: Math.min(1000, count-offset)}, (_,j) => factory(offset+j));
      hash.update(JSON.stringify(docs));
      await coll.insertMany(docs, {ordered: false});
    }
    assert.equal(await coll.countDocuments({_id: new RegExp(`^lab6-seed-${name === 'event_pages' ? 'page' : 'feedback'}-`)}), count);
  }
  await fill('event_pages', PAGE_COUNT, i => page(i, events[i % events.length].pgEventId));
  await fill('visitor_feedback', FEEDBACK_COUNT, i => feedback(i,rng));
  await db.collection('editorial_collections').replaceOne({_id: 'lab6-seed-collection'}, {
    _id: 'lab6-seed-collection', schemaVersion: 1, title: 'Lab6 visitor guides', kind: 'thematic',
    pageSlugs: [id('seed-page',1)], curator: {alias: 'lab6-editor'}
  }, {upsert: true});
  const report = {passed: true, seed: SEED, pages: PAGE_COUNT, feedback: FEEDBACK_COUNT,
    source: 'Existing Lab5 pg_events.json (PostgreSQL export, not a new event source)',
    pgEventIds: events.map(e => String(e.pgEventId)), sha256: hash.digest('hex'), timestamp: new Date()};
  await save('seed.json', report);
  passed(`deterministic seed=${SEED}: ${PAGE_COUNT} pages, ${FEEDBACK_COUNT} feedback; sha256=${report.sha256}`);
}
