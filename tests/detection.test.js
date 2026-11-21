const assert = require('node:assert/strict');
const {approval} = require('../browser-extension/detection');
for (const label of ['Allow once', 'Approve', 'Allow for this session', 'Yes, proceed', 'Yes, and don’t ask again for this command']) assert.equal(approval(label), true, label);
for (const label of ['Continue', 'Yes', 'Run', 'Allow', 'Confirm']) {
  assert.equal(approval(label), false, `${label} without approval context`);
  assert.equal(approval(label, 'Codex requires approval to run this command'), true, label);
}
for (const label of ['Copy', 'Send', 'Stop generating', 'Request permission', 'Tell me how to approve', 'Disallow', 'Approval history']) assert.equal(approval(label, 'requires approval'), false, label);
assert.equal(approval('  ALLOW   ONCE  '), true);
console.log('Detection: 23 positive/negative cases passed');
