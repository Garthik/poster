import {TX_OPTIONS, sleep} from './lib.mjs';

export class CommitUncertainError extends Error {
  constructor(operationId,cause) {
    super(`Commit result remains unknown for ${operationId}; inspect receipt, retry ONLY the same operation ID`,{cause});
    this.operationId=operationId;
  }
}
export const hasLabel = (error,label) => typeof error?.hasErrorLabel === 'function' && error.hasErrorLabel(label);

// Core API: body retry and commit retry have different scopes. Never rerun a body
// because its commit reply was lost. The operation receipt is written in the same tx.
export async function runTransaction(session,operationId,body,options={}) {
  const {maxAttempts=4,maxCommitAttempts=5,pause=sleep,onRetry=()=>{},commit=()=>session.commitTransaction()}=options;
  let totalCommits=0;
  for(let attempt=1;attempt<=maxAttempts;attempt++) {
    session.startTransaction(TX_OPTIONS);
    try {
      const value=await body(session,attempt);
      for(let commitAttempt=1;commitAttempt<=maxCommitAttempts;commitAttempt++) {
        totalCommits++;
        try {
          await commit(session);
          return {value,attempt,commitAttempts:totalCommits};
        } catch(error) {
          if(!hasLabel(error,'UnknownTransactionCommitResult')) throw error;
          onRetry({label:'UnknownTransactionCommitResult',scope:'commit',attempt,commitAttempt});
          if(commitAttempt===maxCommitAttempts) throw new CommitUncertainError(operationId,error);
          await pause(Math.min(200,25*commitAttempt));
        }
      }
    } catch(error) {
      if(error instanceof CommitUncertainError) throw error;
      if(session.inTransaction()) {
        try { await session.abortTransaction(); } catch { /* Preserve the original error. */ }
      }
      if(!hasLabel(error,'TransientTransactionError') || attempt===maxAttempts) throw error;
      onRetry({label:'TransientTransactionError',scope:'transaction',attempt});
      await pause(Math.min(200,25*attempt));
    }
  }
  throw new Error('Invalid retry limits');
}
