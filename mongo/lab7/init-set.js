const check = require('node:assert/strict');
const admin = db.getSiblingDB('admin');
const hosts = process.env.RS_HOSTS.split(',');
const name = process.env.RS_NAME;
const hello = admin.hello();
if (!hello.setName) {
  const config = {_id: name, members: hosts.map((host, i) => ({
    _id: i, host: host + ':27017', priority: hosts.length > 1 && i === 0 ? 2 : 1
  }))};
  if (name === 'cfg7') config.configsvr = true;
  check.equal(admin.runCommand({replSetInitiate: config}).ok, 1);
}
let elected = false;
for (let i=0; i<120; i++) {
  const state = admin.hello();
  if (state.setName === name && state.primary) { elected = true; break; }
  sleep(1000);
}
check(elected, 'Election timed out for ' + name);
print('Ready: ' + name + ' (' + hosts.join(', ') + ')');
