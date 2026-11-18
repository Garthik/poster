# Actual index write/storage measurements

Identical 6000 documents, SHA256 27242f649159ff746747c97a71e0158845ed08a551a09d5092f0df9a8b95d2e5. 5 runs/phase; 1 warmup each. Majority+journal acknowledged. Baseline has _id and Lab5 pageSlug/moderation index; after adds lab6_feedback_page_moderation_created_id.

|Phase|Insert median ms|Insert docs/s|Update median ms|Update docs/s|Index bytes|Storage bytes|
|---|---:|---:|---:|---:|---:|---:|
|before|160.859|37299.8|342.957|17494.9|3133440|5566464|
|after|194.922|30781.6|480.273|12492.9|5189632|5447680|

Indexes require maintenance on insertion and on updates of createdAt. Timing direction is not asserted. collStats reports allocated compressed storage and index bytes, which can lag writes/checkpoints and retain high-water allocations. Dedicated persistent collections are emptied, never dropped; allocation is not a per-document cost. Do not infer a universal speed ratio from one host.
