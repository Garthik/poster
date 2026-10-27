// MongoDB editorial domain only. PostgreSQL owns events, prices, orders and tickets.
const database = db.getSiblingDB('ticket_platform_docs');
function applyValidation(name, schema) {
  const options = { validator: { $jsonSchema: schema }, validationLevel: 'strict', validationAction: 'error' };
  if (database.getCollectionNames().includes(name)) {
    const command = database.runCommand({ collMod: name, ...options });
    if (!command.ok) throw new Error(`collMod failed for ${name}: ${tojson(command)}`);
  } else database.createCollection(name, options);
}
const text = (min=1,max=2000) => ({bsonType:'string', minLength:min, maxLength:max});
const slug = {bsonType:'string', pattern:'^[a-z0-9]+(?:-[a-z0-9]+)*$'};
applyValidation('event_pages', {
  bsonType: 'object', required: ['_id','schemaVersion','pgEventId','headline','status','sections','keywords'],
  properties: {
    _id: slug, schemaVersion: {bsonType:'int', enum:[1,2]}, pgEventId: {bsonType:'string',pattern:'^[0-9]+$'},
    headline: text(5,180), summary: text(10,500), status: {enum:['draft','published']},
    keywords:{bsonType:'array', maxItems:12, uniqueItems:true, items:text(2,40)},
    sections:{bsonType:'array', maxItems:15, items:{
      bsonType:'object', required:['heading','body'],
      properties:{heading:text(2,100),body:text(10,2000)}
    }},
    editor:{bsonType:'object', required:['alias'], properties:{alias:text(2,80)}},
    readingMinutes:{bsonType:'int',minimum:1,maximum:60}
  },
  // Business rule: published pages require a summary and at least one section.
  allOf:[
    {oneOf:[
      {properties:{status:{enum:['draft']}}},
      {required:['summary'], properties:{status:{enum:['published']},summary:text(10,500),sections:{minItems:1}}}
    ]},
    {oneOf:[
      {properties:{schemaVersion:{enum:[1]}}},
      {required:['readingMinutes'],properties:{schemaVersion:{enum:[2]},readingMinutes:{bsonType:'int',minimum:1,maximum:60}}}
    ]}
  ]
});
applyValidation('editorial_collections', {
  bsonType:'object', required:['_id','schemaVersion','title','kind','pageSlugs'],
  properties:{
    _id:slug, schemaVersion:{bsonType:'int',enum:[1,2]}, title:text(4,120),
    kind:{enum:['manual','thematic']},
    // Business rules: a collection is bounded and pages cannot repeat.
    pageSlugs:{bsonType:'array',minItems:1,maxItems:20,uniqueItems:true,items:slug},
    curator:{bsonType:'object', required:['alias'],properties:{alias:text(2,80)}}
  }
});
applyValidation('visitor_feedback', {
  bsonType:'object', required:['_id','schemaVersion','pageSlug','authorAlias','rating','body','moderation'],
  properties:{
    _id:slug, schemaVersion:{bsonType:'int',enum:[1,2]}, pageSlug:slug,
    authorAlias:text(2,60), rating:{bsonType:'int',minimum:1,maximum:5},
    body:text(5,800), moderation:{enum:['pending','approved','rejected']},
    createdAt:{bsonType:'date'}
  }
});
database.event_pages.createIndex({pgEventId:1});
database.event_pages.createIndex({status:1,keywords:1});
database.editorial_collections.createIndex({pageSlugs:1});
database.visitor_feedback.createIndex({pageSlug:1,moderation:1});
print('OK: schema validation and indexes installed for 3 collections');
