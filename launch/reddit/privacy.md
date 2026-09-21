Gate: none listed, standard sub norms apply, keep it about the privacy angle not a sales pitch.

Title: Made a browser that collects literally nothing, because it doesn't do enough to collect from

Body:
Most privacy browsers add a tracker blocker, a VPN, or a sync service on top of the rendering engine, and each of those additions is itself something that has to phone home or store state somewhere. I went the other direction and built one that just doesn't have those layers.

Madobe is a WKWebView, the same engine Safari uses, wrapped in the smallest SwiftUI shell I could write. Type a host and it loads, type words and it searches DuckDuckGo instead of a tracking-heavy default. Tabs live in memory for the session and disappear when you quit. No account, no bookmarks synced anywhere, no analytics SDK, nothing to opt out of because nothing was built in.

It's free, runs on Mac, iPhone and iPad, and the source is public if you want to check the collects-nothing claim yourself.

Web: https://madobe.heyitsmejosh.com
App Store: https://apps.apple.com/app/id6809355192
GitHub: https://github.com/nulljosh/madobe
