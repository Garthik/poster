import test from 'node:test';
import assert from 'node:assert/strict';
import {median,stages,indexNames,csv} from '../../mongo/lab6/lib.mjs';
import {random,feedback} from '../../mongo/lab6/data.mjs';

test('median handles odd/even series, preserves input, rejects missing/nonfinite samples',()=>{
  const values=[20,1,9,3,2]; assert.equal(median(values),3); assert.deepEqual(values,[20,1,9,3,2]);
  assert.equal(median([1,2,8,9]),5); assert.equal(median([0,0,0,1,1]),0);
  assert.throws(()=>median([])); assert.throws(()=>median([NaN]));
});
test('plans count only winning/executed stages, excluding rejected alternatives',()=>{
  const plan={queryPlanner:{winningPlan:{stage:'FETCH',inputStage:{stage:'IXSCAN',indexName:'lab6_good'}},
    rejectedPlans:[{stage:'SORT',inputStage:{stage:'COLLSCAN',indexName:'bad'}}]},
    executionStats:{executionStages:{stage:'LIMIT',inputStage:{stage:'FETCH',inputStage:{stage:'IXSCAN'}}}}};
  assert.deepEqual(stages(plan),['FETCH','IXSCAN','LIMIT']); assert.deepEqual(indexNames(plan),['lab6_good']);
});
test('CSV escapes commas, quotes, and actual line breaks',()=>{
  assert.equal(csv([{a:'x,y',b:'say "yes"\nnext'}]),'"a","b"\n"x,y","say ""yes""\nnext"\n');
});
test('fixtures are deterministic for same seed and change with a different seed',()=>{
  const generate=seed=>{const rng=random(seed);return Array.from({length:20},(_,i)=>feedback(i,rng));};
  assert.deepEqual(generate(20261104),generate(20261104)); assert.notDeepEqual(generate(20261104),generate(42));
  for(const doc of generate(42)) assert(doc.rating>=1 && doc.rating<=5 && doc.createdAt instanceof Date);
});
