import fs from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
import {assert, integer} from './lib.mjs';

export const SEED = integer('LAB6_SEED', 20261104, 0);
export const PAGE_COUNT = integer('LAB6_PAGE_COUNT', 12000, 1000);
export const FEEDBACK_COUNT = integer('LAB6_FEEDBACK_COUNT', 60000, 10000);
export function random(seed) {
  let state = seed >>> 0;
  return () => { state = (Math.imul(state, 1664525) + 1013904223) >>> 0; return state / 4294967296; };
}
export const id = (prefix, i) => `lab6-${prefix}-${String(i).padStart(6, '0')}`;
export function page(i, pgEventId, prefix = 'seed-page') {
  return {_id: id(prefix,i), schemaVersion: 1, pgEventId: String(pgEventId),
    headline: `Visitor guide ${String((i * 7919) % PAGE_COUNT).padStart(6,'0')}`,
    summary: 'Practical information about visiting the event and reaching the venue.',
    status: i % 4 === 0 ? 'draft' : 'published', keywords: ['visit','guide'],
    sections: [{heading: 'Before visiting', body: 'Arrive early and check the official event information.'}],
    editor: {alias: `editor-${String(i % 20).padStart(2,'0')}`}};
}
export function feedback(i, rng, prefix = 'seed-feedback') {
  return {_id: id(prefix,i), schemaVersion: 1, pageSlug: id('seed-page', i % 64),
    authorAlias: `reader-${i % 500}`, rating: 1 + Math.floor(rng()*5),
    body: 'Useful visitor feedback about the event information and the visit. '.repeat(4),
    moderation: ['approved','pending','approved','rejected','approved'][Math.floor(rng()*5)],
    createdAt: new Date(Date.UTC(2026,0,1) + Math.floor(rng()*30000000000))};
}
export async function pgEvents() {
  const filename = process.env.LAB6_PG_SNAPSHOT || fileURLToPath(new URL('../../artifacts/lab5/pg_events.json',import.meta.url));
  const events = JSON.parse(await fs.readFile(filename, 'utf8'));
  assert(Array.isArray(events) && events.length >= 2 && events.every(e => /^[0-9]+$/.test(String(e.pgEventId))),
    'Need the real Lab5 PG event snapshot; run Lab5 sync if absent');
  return events;
}
