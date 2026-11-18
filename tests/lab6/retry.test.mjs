import test from 'node:test';
import assert from 'node:assert/strict';
import {runTransaction,CommitUncertainError} from '../../mongo/lab6/transaction-retry.mjs';

const labeled=label=>Object.assign(new Error(label),{hasErrorLabel:value=>value===label});
function session(commit=async()=>{}) {
  return {starts:0,aborts:0,commits:0,active:false,
    startTransaction(){this.starts++;this.active=true;},inTransaction(){return this.active;},
    async abortTransaction(){this.aborts++;this.active=false;},
    async commitTransaction(){this.commits++;await commit(this.commits);this.active=false;}};
}
const pause=async()=>{};
test('TransientTransactionError aborts and reruns the entire body',async()=>{
  const s=session(),retry=[];let bodies=0;
  const result=await runTransaction(s,'op',async()=>{if(++bodies===1)throw labeled('TransientTransactionError');return 7;},{pause,onRetry:e=>retry.push(e)});
  assert.equal(result.value,7);assert.equal(bodies,2);assert.equal(s.aborts,1);assert.equal(s.commits,1);
  assert.equal(retry[0].scope,'transaction');
});
test('UnknownTransactionCommitResult retries the same commit without rerunning body',async()=>{
  const s=session(async count=>{if(count===1)throw labeled('UnknownTransactionCommitResult');});let bodies=0;
  const result=await runTransaction(s,'op',async()=>++bodies,{pause});
  assert.equal(bodies,1);assert.equal(s.starts,1);assert.equal(s.aborts,0);assert.equal(result.commitAttempts,2);
});
test('unknown commit exhaustion exposes stable operation ID and does not start another body',async()=>{
  const s=session(async()=>{throw labeled('UnknownTransactionCommitResult');});let bodies=0;
  await assert.rejects(runTransaction(s,'stable-op',async()=>++bodies,{pause,maxCommitAttempts:3}),e=>e instanceof CommitUncertainError && e.operationId==='stable-op');
  assert.equal(bodies,1);assert.equal(s.commits,3);assert.equal(s.aborts,0);
});
test('transient body retries are bounded; terminal failure is propagated',async()=>{
  const s=session();let bodies=0;
  await assert.rejects(runTransaction(s,'op',async()=>{bodies++;throw labeled('TransientTransactionError');},{pause,maxAttempts:3}),/TransientTransactionError/);
  assert.equal(bodies,3);assert.equal(s.aborts,3);assert.equal(s.commits,0);
});
test('ordinary business errors abort immediately and do not retry',async()=>{
  const s=session();let bodies=0;
  await assert.rejects(runTransaction(s,'op',async()=>{bodies++;throw new Error('capacity');},{pause}),/capacity/);
  assert.equal(bodies,1);assert.equal(s.starts,1);assert.equal(s.aborts,1);
});
test('TransientTransactionError at commit restarts body, preserving retry scope',async()=>{
  const s=session(async count=>{if(count===1)throw labeled('TransientTransactionError');});let bodies=0;
  const result=await runTransaction(s,'op',async()=>++bodies,{pause});
  assert.equal(result.attempt,2);assert.equal(bodies,2);assert.equal(s.aborts,1);
});
