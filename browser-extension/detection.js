(function (root) {
  const normalize = s => String(s || '').toLowerCase().replace(/\s+/g, ' ').trim();
  const strong = new Set(['allow once', 'allow this time', 'allow for this session', 'allow for session', 'allow always', 'always allow', 'approve', 'approve once', 'approve session', 'approve for this session', 'approve and run', 'allow and run', 'yes, proceed', 'yes, run', 'run command', 'grant permission']);
  function approval(label, context = '') {
    const s = normalize(label);
    if (strong.has(s) || /^yes, and don['’]t ask again/.test(s) || /^allow for this /.test(s)) return true;
    return ['allow', 'yes', 'continue', 'run', 'confirm'].includes(s) && /requires approval|approval required|requesting approval|needs your approval|permission required|requesting permission|allow chatgpt|allow codex|would you like to run|do you want to run|allow this (command|action|tool)|wants to|requires your permission|do you approve|allow access|grant access/.test(normalize(context));
  }
  root.PermissionBellDetection = { normalize, approval };
  if (typeof module !== 'undefined') module.exports = root.PermissionBellDetection;
})(globalThis);
