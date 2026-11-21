# Codex Permission Bell

A local macOS menu bar app that sounds an alert and sends a notification when an AI approval control appears. It reminds you every 60 seconds while the request remains visible to the detector. It never clicks approval buttons.

## Build and install

Requires macOS 13 or newer, Xcode command-line tools, and Python 3. Node.js is needed only for JavaScript tests. The app is built for the Mac’s own architecture and is locally signed, not notarized for distribution.

```sh
git clone https://github.com/nirvaan-gupta/Codex-Permission-Bell.git
cd Codex-Permission-Bell
./build.sh
./install.sh
open "$HOME/Applications/Permission Bell/Permission Bell.app"
```

The build produces `dist/Permission Bell.app` and `dist/browser-extension`. The installer copies both into `~/Applications/Permission Bell`. After quitting an existing installation, use `./install.sh --update` to replace it. Replacing a locally signed build can require repairing its Accessibility permission again.

## Use

Open **Permission Bell.app** inside `~/Applications/Permission Bell`. Click its bell in the menu bar for status, waiting apps, pause/resume, a test notification, and Start at login. Keep the installed app and browser-extension folder together at that location after setup.

One-time setup:

1. In System Settings → Privacy & Security → Accessibility, enable Permission Bell. The setup window has a shortcut.
2. In System Settings → Notifications → Permission Bell, enable notifications. Choose **Alerts** for persistent notifications at the top right. Enable notification display while using full-screen apps if that option is available. Focus may suppress banners; audible system volume is required for sound.
3. In Chrome, open `chrome://extensions`, enable **Developer mode**, choose **Load unpacked**, and select `~/Applications/Permission Bell/browser-extension`. Reload existing ChatGPT/Claude tabs once after installation. Use the same steps in each Chrome profile you use for AI work. The extension needs the Mac app running.
4. Select **Start at login** in the bell menu, then **Test sound & notification**.

The extension sends a heartbeat about every 20–30 seconds. Status says “connected” once the app receives one. A `!` extension badge means the local app could not be reached.

## Coverage and limits

- Native monitor: ChatGPT / Codex, Claude, and VS Code. Scans their accessibility windows about every three seconds, including windows on other Spaces. Only controls exposed by the app’s accessibility tree can be detected. Inactive editor tabs, minimized windows or virtualized content may not expose their controls.
- Chrome extension: `chatgpt.com`, `chat.openai.com`, and `claude.ai`. Observes live page changes in background tabs without switching tabs. Chrome may throttle frozen tabs; discarded tabs cannot run their detector until loaded. Reload existing tabs after adding the extension. Browser fallback uses accessibility for AI-titled browser windows when the Chrome extension is not connected.
- Approval labels and nearby request wording are matched locally. This is a UI detector, not an official approval-event API. New wording, languages other than English, embedded cross-origin frames, canvas-only UI, and future product changes can require updates. It does not detect every permission dialog in every app.
- Notifications follow macOS Focus and display policies. The app plays its sound separately from notification delivery. A muted/sleeping Mac cannot make an audible alert.
- Browser alerts clear as soon as a resolved state arrives, or after 90 seconds without a heartbeat (for example, closing the browser). Native alerts clear after three scans without the approval. Scan time varies with app responsiveness. Click an alert to activate its app/browser; it does not locate a particular browser tab.
- The extension currently activates Google Chrome on notification clicks. Chromium alternatives can load the extension, but automatic browser activation targets Chrome.

## Privacy

No cloud service, API key, screenshots, analytics, conversation storage, or chat-text transmission. Native scanning reads UI labels/text in supported apps into memory to identify approval controls. The browser reads visible control labels and nearby request text locally, then sends only a tab number, AI hostname, browser identifier, and pending/not-pending flag to `127.0.0.1:18473`. The loopback listener requires a randomly generated shared token, rejects webpage origins, and is not bound to the LAN. It stores pending state only in memory.

Accessibility is a broad macOS permission even though this app uses it only to read controls. Revoke it at any time in System Settings. Remove the extension in Chrome to revoke its site access.

## Troubleshooting: no sound for a VS Code approval

1. Open the bell menu’s **Setup & status** window. It must say **Accessibility: enabled** and **Notifications: enabled**. An “on” switch in System Settings alone does not prove the running app has access.
2. If the app still says **needs permission**, open System Settings → Privacy & Security → Accessibility. Select the **Permission Bell.app row**, remove it with the minus button, then use the plus button to add `~/Applications/Permission Bell/Permission Bell.app` explicitly. Authenticate with Touch ID/password if macOS asks. Enable its switch. Restart Permission Bell if needed.
3. Click **Test sound & notification** and check system volume and Focus settings. Ensure monitoring is not paused.
4. Keep the approval panel available in the VS Code window. Controls inside an inactive editor tab might not be exposed to Accessibility.

A stale Accessibility record was the confirmed cause of a missed VS Code alert during local setup. Removing the old record and adding the installed app changed its status to enabled. A synthetic approval subsequently triggered an alert confirmed by the user. This validates the native detector and alert path; every VS Code layout and approval type has not been tested.

## Verify

```sh
./build.sh
node tests/detection.test.js
node tests/content.test.js
python3 tests/build_test.py
swiftc -module-cache-path .build-cache Sources/Detection.swift tests/DetectionTests.swift -o .build-cache/detection-tests
.build-cache/detection-tests
python3 tests/bridge_test.py  # app must be running; negative connection/security tests
```

The build stages generated Swift source in a temporary directory, signs the app, and copies build outputs into `dist/`. A random per-installation bridge token is stored in ignored `.local/bridge-token` (mode 0600), then substituted into generated Swift and extension files. Tracked source keeps a placeholder; builds do not modify it. Keep `.local/` to preserve the token across rebuilds. Do not publish generated builds or the local token as public source.

Automated tests cover label matching, enabled/visible browser controls, and local bridge request validation. The bridge integration test needs the matching app running. OS permission, sound output, and real app layout checks require manual testing on macOS.

## Remove

Turn off Start at login in the bell menu and quit Permission Bell. Remove the extension at `chrome://extensions`. Revoke Permission Bell under Accessibility and Notifications if desired. Then move `~/Applications/Permission Bell` to Trash; the cloned source folder may be removed separately. No launch scripts or Codex configuration changes are installed.
