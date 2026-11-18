import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {client,save} from './lib.mjs';
import {seed} from './seed.mjs';
import {benchmark} from './benchmark.mjs';
import {bulk} from './bulk.mjs';
import {transactions} from './transactions.mjs';
import {indexWrite} from './index-write.mjs';
import {clusterStatus,failoverClient} from './cluster.mjs';
import {check} from './check.mjs';

const command=process.argv[2];
let mongo;
try {
  if(command==='test') {
    const result=spawnSync(process.execPath,['--test',fileURLToPath(new URL('../../tests/lab6/retry.test.mjs',import.meta.url)),
      fileURLToPath(new URL('../../tests/lab6/metrics.test.mjs',import.meta.url))],{encoding:'utf8'});
    process.stdout.write(result.stdout || ''); process.stderr.write(result.stderr || '');
    await save('unit-tests.tap',(result.stdout || '')+(result.stderr || ''));
    if(result.error) throw result.error;
    process.exitCode=result.status ?? 1;
  } else {
    const commands={seed,benchmark,bulk,transaction:transactions,'index-write':indexWrite,status:clusterStatus,
      check:m=>check(m,{withFailover:process.argv.includes('--with-failover')}),'failover-client':failoverClient};
    if(!commands[command]) throw new Error('Unknown Lab6 command: '+command);
    mongo=await client();
    await commands[command](mongo);
  }
} catch(error) {
  // Never log connection strings, environment, credentials, or full MongoClient objects.
  const failure={command,name:error.name,message:error.message,code:error.code,
    labels:error.errorLabels,timestamp:new Date()};
  console.error('FAIL:',failure);
  await save(`logs/last-failure-${command}.json`,failure).catch(()=>{});
  process.exitCode=1;
} finally { if(mongo) await mongo.close(); }
