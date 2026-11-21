const TOKEN = '__BRIDGE_TOKEN__';
const HOSTS = new Set(['chatgpt.com', 'chat.openai.com', 'claude.ai']);
async function relay(tab, pending) {
  let url;
  try { url = new URL(tab.url); } catch { return; }
  if (!HOSTS.has(url.hostname)) return;
  try {
    const response = await fetch('http://127.0.0.1:18473/event', {
      method: 'POST', headers: {'Content-Type': 'application/json', 'X-Permission-Bell-Token': TOKEN},
      body: JSON.stringify({tab: tab.id, pending, host: url.hostname, browser: 'com.google.Chrome'}),
      signal: AbortSignal.timeout(4000)
    });
    await chrome.action.setBadgeText({text: response.ok ? '' : '!'});
    await chrome.action.setTitle({title: response.ok ? 'Permission Bell connected' : 'Open Permission Bell on your Mac'});
  } catch {
    await chrome.action.setBadgeText({text: '!'});
    await chrome.action.setBadgeBackgroundColor({color: '#B44A22'});
    await chrome.action.setTitle({title: 'Open Permission Bell on your Mac'});
  }
}
chrome.runtime.onMessage.addListener((message, sender) => {
  if (message.type === 'approval-state' && typeof message.pending === 'boolean' && sender.tab) {
    chrome.storage.session.set({[String(sender.tab.id)]: {host: new URL(sender.tab.url).hostname}});
    relay(sender.tab, message.pending);
  }
});
async function clearTab(id) {
  const key = String(id);
  const old = (await chrome.storage.session.get(key))[key];
  if (old) await relay({id, url: 'https://' + old.host}, false);
  await chrome.storage.session.remove(key);
}
chrome.tabs.onRemoved.addListener(clearTab);
chrome.tabs.onUpdated.addListener((id, change) => { if (change.status === 'loading') clearTab(id); });
chrome.alarms.create('rescan', {periodInMinutes: 0.5});
chrome.alarms.onAlarm.addListener(async () => {
  const tabs = await chrome.tabs.query({url: ['https://chatgpt.com/*', 'https://chat.openai.com/*', 'https://claude.ai/*']});
  for (const tab of tabs) chrome.tabs.sendMessage(tab.id, {type: 'rescan'}).catch(() => {});
});
chrome.action.onClicked.addListener(async () => {
  const tabs = await chrome.tabs.query({url: ['https://chatgpt.com/*', 'https://chat.openai.com/*', 'https://claude.ai/*']});
  for (const tab of tabs) chrome.tabs.sendMessage(tab.id, {type: 'rescan'}).catch(() => {});
});
