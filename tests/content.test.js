const vm = require('node:vm');
const fs = require('node:fs');
const assert = require('node:assert/strict');
function detect({label = 'Allow once', context = '', disabled = false, visible = true, aria = null}) {
  const events = [];
  const button = {innerText: label, disabled, value: '', getAttribute: k => k === 'aria-disabled' ? aria : null,
    getClientRects: () => visible ? [{}] : [], closest: () => ({innerText: context})};
  const sandbox = {document: {querySelectorAll: () => [button], documentElement: {}},
    MutationObserver: class {observe() {}}, clearTimeout, setTimeout, setInterval() {},
    getComputedStyle: () => ({visibility: 'visible'}),
    chrome: {runtime: {sendMessage: event => {events.push(event); return Promise.resolve();}, onMessage: {addListener() {}}}}};
  vm.createContext(sandbox);
  vm.runInContext(fs.readFileSync('browser-extension/detection.js', 'utf8'), sandbox);
  vm.runInContext(fs.readFileSync('browser-extension/content.js', 'utf8'), sandbox);
  return events[0].pending;
}
assert.equal(detect({}), true);
assert.equal(detect({disabled: true}), false);
assert.equal(detect({aria: 'true'}), false);
assert.equal(detect({visible: false}), false);
assert.equal(detect({label: 'Continue'}), false);
assert.equal(detect({label: 'Continue', context: 'Requires approval'}), true);
assert.equal(detect({label: 'Copy', context: 'Requires approval'}), false);
console.log('Content script: visibility, enabled state, and context checks passed');
