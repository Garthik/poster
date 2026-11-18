import {MongoClient, BSON} from 'mongodb';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import assert from 'node:assert/strict';

export {assert};
const {EJSON} = BSON;
export const DATABASE = 'ticket_platform_docs';
export const HOSTS = ['mongo1:27101', 'mongo2:27102', 'mongo3:27103'];
export const ART = process.env.LAB6_ARTIFACTS || fileURLToPath(new URL('../../artifacts/lab6/',import.meta.url));
export const WC = {w: 'majority', j: true, wtimeoutMS: 15000};
export const TX_OPTIONS = {readConcern: {level: 'snapshot'}, writeConcern: WC,
  readPreference: 'primary', maxCommitTimeMS: 15000};
export const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
export function integer(name, fallback, minimum = 1) {
  const value = Number(process.env[name] ?? fallback);
  assert(Number.isSafeInteger(value) && value >= minimum, `${name} must be integer >= ${minimum}`);
  return value;
}
export async function client(appName = 'ticket-lab6', root = false, directHost) {
  const secretDir = process.env.LAB6_SECRET_DIR || '/run/secrets';
  const secret = async name => {
    try { return (await fs.readFile(path.join(secretDir, name), 'utf8')).trim(); }
    catch(error) {
      if(error.code!=='ENOENT') throw error;
      return (await fs.readFile(path.join(secretDir,name.replaceAll('_','-')),'utf8')).trim();
    }
  };
  const username = root ? await secret('root_user') : 'lab6_app';
  const password = await secret(root ? 'root_password' : 'app_password');
  // The entire advertised host list resolves both in Compose and in WSL with /etc/hosts.
  const uri = directHost ? `mongodb://${directHost}/?directConnection=true` :
    `mongodb://${HOSTS.join(',')}/?replicaSet=rs0&retryWrites=true`;
  const mongo = new MongoClient(uri, {auth: {username, password}, authSource: 'admin', appName,
    readConcern: {level: 'majority'}, writeConcern: WC, readPreference: 'primary',
    serverSelectionTimeoutMS: 45000, connectTimeoutMS: 5000, socketTimeoutMS: 60000,
    maxPoolSize: 8, monitorCommands: true});
  await mongo.connect();
  return mongo;
}
export async function save(name, data) {
  const filename = path.join(ART, name);
  await fs.mkdir(path.dirname(filename), {recursive: true});
  const body = typeof data === 'string' ? data : EJSON.stringify(data, null, 2, {relaxed: true}) + '\n';
  // Atomic replacement keeps a killed run from leaving a valid-looking half-report.
  await fs.writeFile(filename + '.tmp', body);
  await fs.rename(filename + '.tmp', filename);
}
export async function read(name) { return EJSON.parse(await fs.readFile(path.join(ART, name), 'utf8')); }
export function median(values) {
  assert(values.length > 0 && values.every(Number.isFinite), 'Finite nonempty series');
  const sorted = [...values].sort((a,b) => a-b), mid = Math.floor(sorted.length/2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid-1] + sorted[mid])/2;
}
export function csv(rows) {
  assert(rows.length > 0);
  const keys = Object.keys(rows[0]);
  const cell = value => '"' + String(value ?? '').replaceAll('"', '""') + '"';
  return [keys.map(cell).join(','), ...rows.map(row => keys.map(k => cell(row[k])).join(','))].join('\n') + '\n';
}
export function stages(plan) {
  const result = new Set();
  function walk(value) {
    if (!value || typeof value !== 'object') return;
    if (typeof value.stage === 'string') result.add(value.stage);
    for (const child of Object.values(value)) walk(child);
  }
  // Exclude rejected plans: report only the winning and actually executed stages.
  walk(plan.queryPlanner?.winningPlan);
  walk(plan.executionStats?.executionStages);
  return [...result].sort();
}
export function indexNames(plan) {
  const names = new Set();
  function walk(value) {
    if (!value || typeof value !== 'object') return;
    if (value.indexName) names.add(value.indexName);
    for (const child of Object.values(value)) walk(child);
  }
  walk(plan.queryPlanner?.winningPlan);
  return [...names];
}
export async function dropOwnedIndex(collection, name) {
  assert(name.startsWith('lab6_'), 'Only Sprint 6 indexes can be removed');
  try { await collection.dropIndex(name); } catch (error) { if (error.code !== 27) throw error; }
}
export async function eventually(fn, description, timeout = 120000) {
  const deadline = Date.now() + timeout;
  let last;
  while (Date.now() < deadline) {
    try { const value = await fn(); if (value) return value; } catch (error) { last = error; }
    await sleep(1000);
  }
  throw new Error(`Timed out: ${description}${last ? ' (' + last.message + ')' : ''}`);
}
export function passed(message) { console.log('PASS: ' + message); }
