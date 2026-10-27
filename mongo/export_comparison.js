const fs=require('fs');
const database=db.getSiblingDB('ticket_platform_docs');
const pages=database.event_pages.find({_id:/^pg-event-/},{
  _id:1,schemaVersion:1,pgEventId:1,headline:1,summary:1,status:1,sections:1,keywords:1,readingMinutes:1
}).sort({_id:1}).toArray();
if(pages.length<2)throw new Error('Run sync first');
const rows=pages.map(p=>({slug:p._id,schemaVersion:Number(p.schemaVersion),pgEventId:p.pgEventId,
  headline:p.headline,summary:p.summary,status:p.status,sections:p.sections,keywords:p.keywords,
  ...(p.readingMinutes?{readingMinutes:Number(p.readingMinutes)}:{})}));
fs.writeFileSync('/work/artifacts/mongo_pages.jsonl',rows.map(x=>JSON.stringify(x)).join('\n')+'\n');
// This is a SELECT-equivalent read workload: public editorial cards containing 'visit'.
const cards=database.event_pages.find({status:'published',keywords:'visit',_id:/^pg-event-/},
  {_id:1,headline:1,status:1}).sort({_id:1}).toArray()
  .map(x=>({slug:x._id,headline:x.headline,status:x.status}));
fs.writeFileSync('/work/artifacts/mongo_cards.json',JSON.stringify(cards,null,2)+'\n');
print(`OK: exported ${rows.length} common documents; ${cards.length} matching editorial cards`);
