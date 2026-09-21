Gate: none listed, keep it framed as a tool not an ad.

Title: Browser that defaults to DuckDuckGo instead of Google, and doesn't do much else

Body:
Part of degoogling for me was noticing how many browsers still route your default search through Google even after you've swapped everything else out. I built a small one where that's not a setting to remember, it's just how it works.

Madobe wraps WKWebView, so it's Safari's own engine under the hood, not a new rendering stack to trust. Typed text that looks like a URL loads directly, anything else searches DuckDuckGo. No account, no sync, no telemetry sending anything back to me either.

Free, on the App Store for Mac and iOS, source is open if you want to see exactly what it does with what you type.

Web: https://madobe.heyitsmejosh.com
App Store: https://apps.apple.com/app/id6809355192
GitHub: https://github.com/nulljosh/madobe
