# Architecture

WebKit browser. One SwiftUI file, iOS and macOS from the same code. Address bar, tabs, back/forward/reload. No bookmarks, no sync, no telemetry. Browse the web, not an opinion about browsing.

## How it runs

`LucarneApp.swift` is the sole source file. `resolve()` turns input into a URL (type a host → loads it, type words → DuckDuckGo search). `Page` wraps a `WKWebView` and its navigation delegate. `Tabs` holds the page list. `PageView` renders the chrome (address bar, buttons, tab bar). On macOS and iOS, the same code drives both: only the window size differs.

| File | What it owns |
|---|---|
| `ios/App/LucarneApp.swift` | Everything: URL resolution, WKWebView wrapper, tabs, address bar, back/forward/reload, search bar. One file per Apple best-practice. |
| `ios/Tests/LucarneTests.swift` | Unit tests for URL resolution and tab operations. |
| `ios/project.yml` | xcodegen project definition for iOS and macOS. |
| `landing/index.html` | Landing page: address bar + embedded browser iframe for a live demo. Hero and tagline. |
| `landing/start.html` | Start/home page (what loads when the browser opens with no URL). |
| `wrangler.toml` | Cloudflare Worker deployment for the landing page. |

## Design

- WebKit does all browsing; no custom rendering, history, or cookie layers. Use the OS when it has it.
- Tabs are in-memory only. No persistence (yet).
- App delegates to OS services for everything (WebKit for browsing, DuckDuckGo for search, URL schemes for mailto: and tel:).
