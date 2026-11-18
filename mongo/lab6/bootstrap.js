// Invoked locally inside mongo1 after the final authenticated mongod is healthy.
const fs = require('fs');
const bootAssert = require('node:assert/strict');
function worked(result) {
  if (result.ok !== 1) throw new Error('Bootstrap command failed: ' + JSON.stringify(result));
  return result;
}
const rootUser = fs.readFileSync('/run/secrets/root_user', 'utf8').trim();
const rootPassword = fs.readFileSync('/run/secrets/root_password', 'utf8').trim();
const admin = db.getSiblingDB('admin');
if (!admin.auth(rootUser, rootPassword)) throw new Error('Root authentication failed');
const expectedHosts = ['mongo1:27101', 'mongo2:27102', 'mongo3:27103'];
let initial;
try { initial = admin.runCommand({replSetGetStatus: 1}); }
catch (error) { if (error.code !== 94) throw error; initial = {code:94}; }
if (initial.code === 94) {
  worked(admin.runCommand({replSetInitiate: {
    _id: 'rs0', members: expectedHosts.map((host, _id) => ({_id, host, priority: 1, votes: 1})),
    settings: {electionTimeoutMillis: 5000}
  }}));
} else worked(initial);
let elected = false;
for (let n = 0; n < 120; n++) {
  const hello = admin.runCommand({hello: 1});
  if (hello.primary) { elected = true; break; }
  sleep(1000);
}
if (!elected) throw new Error('PRIMARY election timed out');
// mongo1 need not be primary when this script is rerun.
const primaryHost = admin.runCommand({hello: 1}).primary;
const primaryConnection = new Mongo(`mongodb://${primaryHost}/?directConnection=true`);
const primaryAdmin = primaryConnection.getDB('admin');
bootAssert(primaryAdmin.auth(rootUser, rootPassword), 'Authenticate current primary');
const config = worked(primaryAdmin.runCommand({replSetGetConfig: 1})).config;
bootAssert.equal(config._id, 'rs0');
bootAssert.equal(config.members.map(m => m.host).sort().join(','), expectedHosts.slice().sort().join(','));
bootAssert(config.members.every(m => m.votes === 1 && m.priority > 0 && !m.arbiterOnly), 'Three data-bearing voters');
const appPassword = fs.readFileSync('/run/secrets/app_password', 'utf8').trim();
if (!primaryAdmin.getUser('lab6_app')) {
  primaryAdmin.createUser({user: 'lab6_app', pwd: appPassword, roles: [
    {role: 'readWrite', db: 'ticket_platform_docs'}, {role: 'clusterMonitor', db: 'admin'}
  ]}, {w: 'majority', wtimeout: 15000});
}
// Reuse the exact Lab5 validators and business indexes in the separate replica set.
db = primaryConnection.getDB('ticket_platform_docs');
load('/work/mongo/schema.js');
print('PASS: rs0 initialized; Lab5 schema reused; application user ready');
