#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
stage=$(mktemp -d /private/tmp/permissionbell-build.XXXXXX)
app="$stage/Permission Bell.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" .build-cache dist
python3 scripts/prepare_build.py "$stage"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PermissionBell</string>
<key>CFBundleIdentifier</key><string>local.permissionbell.app</string>
<key>CFBundleName</key><string>Permission Bell</string>
<key>CFBundleDisplayName</key><string>Permission Bell</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSAccessibilityUsageDescription</key><string>Detect approval buttons in AI app windows so you hear when permission is waiting.</string>
</dict></plist>
PLIST
swiftc -O -swift-version 5 -module-cache-path .build-cache Sources/Detection.swift "$stage/main.swift" -o "$app/Contents/MacOS/PermissionBell" -framework AppKit -framework ApplicationServices -framework UserNotifications -framework Network -framework ServiceManagement
codesign --force --sign - --identifier local.permissionbell.app "$app"
ditto --norsrc "$app" "dist/Permission Bell.app"
python3 - <<'PYATTR'
import subprocess
from pathlib import Path
for path in [Path("dist/Permission Bell.app"), *Path("dist/Permission Bell.app").rglob("*")]:
    for name in ("com.apple.FinderInfo", "com.apple.ResourceFork"):
        try:
            subprocess.run(["xattr", "-d", name, str(path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
        except OSError:
            pass
PYATTR
codesign --verify --deep --strict "dist/Permission Bell.app"
print 'Built dist/Permission Bell.app and dist/browser-extension'
