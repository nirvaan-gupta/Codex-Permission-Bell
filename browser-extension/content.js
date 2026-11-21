(() => {
  let timer, last = null;
  function scan(force = false) {
    const buttons = document.querySelectorAll('button, [role="button"], input[type="submit"]');
    let pending = false;
    for (const button of buttons) {
      if (button.disabled || button.getAttribute('aria-disabled') === 'true' || !button.getClientRects().length || getComputedStyle(button).visibility === 'hidden') continue;
      const label = button.innerText || button.getAttribute('aria-label') || button.value || '';
      // Context stays close to the control, avoiding matches in old chat messages.
      const region = button.closest('[role="dialog"], [role="alertdialog"], form') || button.parentElement?.parentElement?.parentElement;
      const context = (region?.innerText || '').slice(0, 16000);
      if (PermissionBellDetection.approval(label, context)) { pending = true; break; }
    }
    if (force || pending !== last) {
      last = pending;
      chrome.runtime.sendMessage({type: 'approval-state', pending}).catch(() => {});
    }
  }
  new MutationObserver(() => { clearTimeout(timer); timer = setTimeout(() => scan(), 250); }).observe(document.documentElement, {subtree: true, childList: true, attributes: true, characterData: true});
  chrome.runtime.onMessage.addListener(message => { if (message.type === 'rescan') scan(true); });
  setInterval(() => scan(true), 20000);
  scan(true);
})();
