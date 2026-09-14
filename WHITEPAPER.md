# Madobe Technical Whitepaper

**v1.0.0** | September 2026

A web browser that writes no browser code. Most third-party browsers exist to
add something (privacy, sync, a vertical tab sidebar), which means carrying
their own rendering or history stack to do it, and that surface is exactly
where bugs and staleness against the real web creep in. Madobe exists to be
the opposite: the thinnest possible chrome around the engine already on the
device, so it inherits Safari's own correctness for free. It is a
`WKWebView` inside a SwiftUI toolbar, shipped for macOS, iOS and iPadOS from
one target.

## Core Mechanic: WebKit Is the Browser

Rendering, JavaScript, networking, cookies, back-forward cache, swipe navigation, reader-safe text sizing, password autofill and content blocking all live inside WebKit. Madobe does not reimplement or wrap any of it, because every one of those is a place a homemade version would be worse than the OS's own and would need its own maintenance forever. Each tab is one `WKWebView` owned by a `Page` object that also acts as its navigation delegate, mirroring five values into SwiftUI state: address, title, loading, can go back, can go forward.

## Address Resolution

One pure function, `resolve`, turns typed text into a URL. Text with a scheme loads as is. A single token with a dot gets `https://` in front. Anything else becomes a DuckDuckGo query, chosen so a browser with no telemetry doesn't turn around and pipe searches through a tracking-heavy default. It is the only logic in the app and the only thing with unit tests beyond the tab list, because it is the only logic that isn't already WebKit's job.

## Tabs

`Tabs` is an array of pages and a current id. Adding appends and selects; closing removes and selects the neighbour, and never closes the last one, so there is always something to look at. Tabs live in memory for the process lifetime. Persisting them is a deliberate omission until there is a reason, since every added feature is a place the app could later behave unexpectedly, and a browser this small earns trust by doing little, reliably.

## Platform Split

The one `#if` per concern rule: `WebView` is an `NSViewRepresentable` on Mac and a `UIViewRepresentable` on iOS, because that is the one place AppKit and UIKit genuinely diverge on how a native view gets hosted. iOS wraps the content in a `NavigationStack` because that is where its toolbar lives; macOS toolbars attach to the window. Keyboard shortcuts (⌘[, ⌘], ⌘R, ⌘T, ⌘W) are declared once and work on both, so muscle memory from one platform carries to the other.

## What Is Deliberately Missing

Bookmarks, history UI, downloads, extensions, sync, telemetry. Each is a feature, and each is also a new place to get something wrong or a new thing to explain to a user, so each gets added when someone using Madobe actually wants it, not before.
