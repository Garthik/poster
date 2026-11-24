const fs = require('fs');
const check = require('node:assert/strict');
const password = fs.readFileSync('/lab-password', 'utf8').trim();
const admin = connect('mongodb://127.0.0.1:27017/admin?serverSelectionTimeoutMS=60000');
check.equal(admin.hello().msg, 'isdbgrid');
function login() {
  try { const result = admin.auth('lab7_admin', password); return result === true || result.ok === 1; } catch { return false; }
}
if (!login()) {
  check.equal(process.env.LAB7_ACTION, 'init');
  admin.createUser({user: 'lab7_admin', pwd: password, roles: ['root']});
  check(login(), 'Cluster authentication failed');
}
const membersA = process.env.LAB7_LAYOUT === 'template' ? ['mongo1','mongo2','mongo3'] : ['mongo1'];
const expected = {shardA: membersA, shardB: ['b']};
if (process.env.LAB7_ACTION === 'init') {
  const present = admin.runCommand({listShards: 1}).shards.map(x => x._id);
  for (const [rs, members] of Object.entries(expected)) {
    if (!present.includes(rs)) {
      check.equal(admin.runCommand({addShard: rs + '/' + members.map(h => h + ':27017').join(',')}).ok, 1);
    }
  }
}
const topology = admin.runCommand({listShards: 1}).shards;
for (const [rs,members] of Object.entries(expected)) {
  const shard = topology.find(s => s._id === rs);
  check(shard);
  check.deepEqual(shard.host.split('/')[1].split(',').sort(), members.map(x=>x+':27017').sort());
}
check.equal(topology.length, 2);
printjson({layout: process.env.LAB7_LAYOUT, version: admin.version(), shards: topology.map(s => s.host)});
