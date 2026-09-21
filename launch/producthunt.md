Name: Madobe

Tagline: A browser that's just an address bar and WebKit

Description: Madobe is a browser with nothing else. One SwiftUI file wraps WebKit for Mac, iPhone and iPad. Type a host and it loads, type words and it searches DuckDuckGo. No bookmarks, no sync, no telemetry. Those get added when there's a reason.

Topics: Productivity, Mac, Open Source

First comment:
I write small apps that do one thing, and most browsers bothered me for the same reason: they exist to add something on top of WebKit, which means carrying their own history stack, sync layer or tracking pipeline to do it. That's exactly where bugs and staleness against the real web creep in.

Madobe is the opposite bet. It's a WKWebView inside a SwiftUI toolbar, one target for Mac, iPhone and iPad, and nothing else. Type an address bar and it resolves the same way real browsers do: a scheme loads as is, a single token with a dot gets https:// in front, anything else searches DuckDuckGo instead of piping you through a tracking-heavy default. Tabs live in memory for the process. Back, forward, reload. That's the whole feature list.

Bookmarks, history UI, sync and telemetry are deliberately missing. Each one is a place to get something wrong or a new thing to explain, so each gets added only when someone using Madobe actually asks for it.

Madobe is Free, and it stays free. Browsers are free by convention, nobody pays for one, so building a business on top of the one thing every OS gives away for free never made sense to me.

Links:
Web: https://madobe.heyitsmejosh.com
App Store: https://apps.apple.com/app/id6809355192
GitHub: https://github.com/nulljosh/madobe
