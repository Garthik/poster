import fs from 'node:fs/promises';
import path from 'node:path';
import {assert, client, save, eventually, sleep, passed, read, DATABASE, HOSTS, ART} from './lib.mjs';
import {id, feedback, random, SEED} from './data.mjs';

export async function clusterStatus(mongo,{record=true}={}) {
  const admin=mongo.db('admin');
  const state=await eventually(async()=>{
    const status=await admin.command({replSetGetStatus:1});
    if(status.members.length!==3 || status.members.filter(m=>m.stateStr==='PRIMARY').length!==1 ||
       status.members.filter(m=>m.stateStr==='SECONDARY').length!==2 || status.members.some(m=>m.health!==1)) return false;
    return status;
  },'one PRIMARY, two healthy SECONDARY members');
  assert.equal(state.set,'rs0');
  assert.deepEqual(state.members.map(m=>m.name).sort(),[...HOSTS].sort());
  // Validate membership/votes with the root control connection; app stays readWrite+monitor.
  const root=await client('ticket-lab6-membership-controller',true);
  let config;
  try { config=(await root.db('admin').command({replSetGetConfig:1})).config; } finally { await root.close(); }
  assert.equal(config.members.length,3);
  assert(config.members.every(m=>m.votes===1 && m.priority>0 && !m.arbiterOnly));
  if(record) await save('replica-status.json',{passed:true,status:state,config,timestamp:new Date()});
  console.log(state.members.map(m=>`${m.name}: ${m.stateStr} health=${m.health}`).join('\n'));
  passed('rs0: 3 data-bearing voters; 1 PRIMARY and 2 SECONDARY');
  return state;
}
export function serviceForHost(host) {
  assert(HOSTS.includes(host),'Unexpected replica-set host');
  return host.split(':')[0];
}
async function signal(name,value='ready\n') { await save(`control/${name}`,value); }
async function waitSignal(name,timeout=120000) {
  await eventually(async()=>{try{return await fs.readFile(path.join(ART,'control',name),'utf8');}catch(e){if(e.code!=='ENOENT')throw e;return false;}},`orchestrator signal ${name}`,timeout);
}
export async function failoverClient(mongo) {
  const started=new Date(),db=mongo.db(DATABASE),coll=db.collection('visitor_feedback');
  assert(await db.collection('event_pages').findOne({_id:id('seed-page',7)}),'Run seed first');
  const before=(await db.admin().command({hello:1})).primary;
  assert(before); serviceForHost(before);
  const rng=random(SEED),beforeDoc={...feedback(0,rng,'failover-before'),pageSlug:id('seed-page',7)},
    afterDoc={...feedback(0,rng,'failover-after'),pageSlug:id('seed-page',7)};
  const topology=[];
  mongo.on('topologyDescriptionChanged',event=>topology.push({at:new Date(),type:event.newDescription.type,
    primary:[...event.newDescription.servers.values()].filter(s=>s.type==='RSPrimary').map(s=>s.address)}));
  let report;
  await coll.deleteMany({_id:/^lab6-failover-/});
  try {
    await coll.insertOne(beforeDoc);
    assert.deepEqual(await coll.findOne({_id:beforeDoc._id}),beforeDoc,'Pre-failure majority read/write');
    await signal('primary-service',serviceForHost(before)+'\n');
    await signal('ready');
    await waitSignal('stopped');
    const electionStart=Date.now();
    const after=await eventually(async()=>{
      const hello=await db.admin().command({hello:1});
      return hello.primary && hello.primary!==before ? hello.primary : false;
    },'different PRIMARY elected',90000);
    assert.notEqual(after,before);
    // Same MongoClient object and full seed-list URI throughout. Driver reselects server.
    assert.deepEqual(await coll.findOne({_id:beforeDoc._id}),beforeDoc,'Acknowledged pre-failure write survives');
    await coll.insertOne(afterDoc);
    assert.deepEqual(await coll.findOne({_id:afterDoc._id}),afterDoc,'Write/read recovered through existing client');
    const recoveryMillis=Date.now()-electionStart;
    await signal('recovered');
    await waitSignal('restarted');
    const restored=await eventually(async()=>{
      const status=await db.admin().command({replSetGetStatus:1});
      const member=status.members.find(m=>m.name===before);
      return member?.stateStr==='SECONDARY' && member.health===1 ? status : false;
    },'stopped primary returns as SECONDARY',150000);
    // Verify actual catch-up on that exact member, not just a status label.
    const secondary=await client('ticket-lab6-returned-node-reader',false,before);
    try {
      await eventually(async()=>await secondary.db(DATABASE).collection('visitor_feedback').findOne(
        {_id:afterDoc._id},{readPreference:'secondary',readConcern:{level:'majority'}}), 'returned node reads post-failover write');
    } finally { await secondary.close(); }
    report={passed:true,before,after,service:serviceForHost(before),recoveryMillis,sameClient:true,
      beforeWriteSurvived:true,afterWriteRead:true,returnedState:'SECONDARY',returnedNodeHasNewWrite:true,
      topology,restoredStatus:restored,started,finished:new Date()};
  } finally { await coll.deleteMany({_id:/^lab6-failover-/}); }
  assert.equal(await coll.countDocuments({_id:/^lab6-failover-/}),0);
  await save('failover.json',{...report,cleaned:true});
  await signal('done');
  passed(`failover ${before} -> ${report.after}; existing client recovered; old primary SECONDARY with new data`);
}
