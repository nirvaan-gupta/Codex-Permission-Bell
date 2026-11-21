#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
destination="$HOME/Applications/Permission Bell"
if [[ -e "$destination" && "${1:-}" != "--update" ]]; then
  print -u2 'Installation folder already exists. Update it manually after quitting the app.'
  exit 1
fi
if [[ ! -x "dist/Permission Bell.app/Contents/MacOS/PermissionBell" || ! -f dist/browser-extension/manifest.json ]]; then
  print -u2 'Run ./build.sh before installing.'
  exit 1
fi
mkdir -p "$destination"
ditto --norsrc 'dist/Permission Bell.app' "$destination/Permission Bell.app"
ditto --norsrc dist/browser-extension "$destination/browser-extension"
cp README.md "$destination/README.md"
python3 - "$destination/Permission Bell.app" <<'PY'
import subprocess, sys
from pathlib import Path
app = Path(sys.argv[1])
for path in [app, *app.rglob('*')]:
    for name in ('com.apple.FinderInfo', 'com.apple.ResourceFork'):
        try:
            subprocess.run(["xattr", "-d", name, str(path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        except OSError:
            pass
PY
codesign --verify --deep --strict "$destination/Permission Bell.app"
print "Installed in $destination"
