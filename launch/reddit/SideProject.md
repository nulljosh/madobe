Gate: none, promotion-friendly. Tell the build story, no bare link.

Title: I built a browser that's just an address bar and WebKit

Body:
Every third-party browser I've tried exists to add something on top of WebKit or Chromium, and every one of those additions is its own maintenance burden and its own place to fall behind the real web. I wanted to know what was left if you stripped a browser down to nothing but the engine already on the device.

Madobe is a WKWebView inside a SwiftUI toolbar. One file, one xcodegen target, ships to Mac, iPhone and iPad. Type an address and it loads. Type words and it searches DuckDuckGo. Back, forward, reload, tabs. No bookmarks, no sync, no telemetry, no account.

The only real logic is a single function that decides how to read what you typed. Everything else, rendering, cookies, autofill, back-forward cache, is WebKit's job, because it's already better at it than anything I'd write.

It's free, it's on the App Store for Mac and iOS, and the source is up on GitHub. Would love feedback on what, if anything, is actually missing.

Web: https://madobe.heyitsmejosh.com
App Store: https://apps.apple.com/app/id6809355192
GitHub: https://github.com/nulljosh/madobe
