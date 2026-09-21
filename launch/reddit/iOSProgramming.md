Gate: requires "Show and Tell" flair, or use the weekly self-promo thread if one is active.

Title: [Show and Tell] Built a browser as one SwiftUI file wrapping WKWebView, shipped to Mac, iPhone and iPad

Body:
Wanted to see how small a real browser could get if I leaned entirely on WebKit instead of adding anything on top of it. Madobe is a WKWebView owned by a Page object that also acts as its own navigation delegate, mirroring five values into SwiftUI state: address, title, loading, can go back, can go forward. WebView itself is an NSViewRepresentable on Mac and a UIViewRepresentable on iOS, the one #if per concern, everything else is shared.

The only app logic beyond that is a single resolve() function that turns typed text into a URL, and it's the only thing with unit tests besides the tab list. Tabs are a plain array held in memory, never persisted.

Free on the App Store, source is up if anyone wants to see how little code it takes.

Web: https://madobe.heyitsmejosh.com
App Store: https://apps.apple.com/app/id6809355192
GitHub: https://github.com/nulljosh/madobe
