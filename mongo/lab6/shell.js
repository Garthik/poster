// Auth without a password in argv/history; can run on any surviving member.
const fs = require('fs');
const shellAssert = require('node:assert/strict');
const shellAdmin = db.getSiblingDB('admin');
shellAssert(shellAdmin.auth(fs.readFileSync('/run/secrets/root_user','utf8').trim(),
  fs.readFileSync('/run/secrets/root_password','utf8').trim()), 'Authentication');
db = db.getSiblingDB('ticket_platform_docs');
print('Authenticated. db = ticket_platform_docs; use db.hello() to locate PRIMARY.');
