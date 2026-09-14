# Lucarne

v1.0.0, WebKit browser. One SwiftUI file, one xcodegen target for iOS and macOS. No web build (it's a browser). Named after the French word for dormer window (ASC name was "Nook" rejected as too common; "Lucarne" was chosen from a list of window-themed names, 40+ alternatives taken).

## Files

- `ios/App/LucarneApp.swift`: everything. `resolve()` turns input into a URL, `Page` wraps one `WKWebView` + nav delegate, `Tabs` holds pages, `PageView` is the chrome.
- `ios/Tests/LucarneTests.swift`: resolve + tabs.
- `landing/`: the page IS a browser (bar + iframe, index.html); hero copy lives in start.html. Deployed via `deploy.sh`.

## Build

```bash
cd ios && xcodegen generate
xcodebuild test -project Lucarne.xcodeproj -scheme Lucarne -destination 'platform=macOS'
xcodebuild build -project Lucarne.xcodeproj -scheme Lucarne -destination 'generic/platform=iOS Simulator'
```

## Rules

- WebKit does the browsing. Don't add a rendering, history or cookie layer; if the OS has it, use it.
- Tabs are in memory. Persist only when someone asks.
- ASC record 6809355192 (created 2026-09-07, iOS platform added; macOS platform added later, both 1.0.0 submitted). Bundle com.nulljosh.lucarne.
