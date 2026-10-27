// Expand/read old + new -> migrate in-place -> eventually contract validation.
// Safe to run repeatedly: only documents with schemaVersion=1 are changed.
const database=db.getSiblingDB('ticket_platform_docs');
const res=database.event_pages.updateMany({schemaVersion:NumberInt(1)},[{
  $set:{
    readingMinutes:{$toInt:{$max:[1,{$ceil:{$divide:[
      {$strLenCP:{$ifNull:['$summary','']}},150
    ]}}]}},
    schemaVersion:NumberInt(2)
  }
}]);
const broken=database.event_pages.countDocuments({schemaVersion:2,readingMinutes:{$exists:false}});
if(broken)throw new Error('Invalid v2 documents: '+broken);
print('OK: migrated '+res.modifiedCount+' event_pages from schemaVersion=1 to 2');
