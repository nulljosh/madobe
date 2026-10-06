<img src="icon.svg" width="80" alt="">

# madobe

![version](https://img.shields.io/badge/version-v1.0.0-blue) ![license](https://img.shields.io/badge/license-MIT-green) [![GitHub](https://img.shields.io/badge/GitHub-nulljosh%2Fmadobe-black?logo=github)](https://github.com/nulljosh/madobe)

A web browser is a text field and a WebKit view. Everything else is opinion. A madobe is a small window in a roof; this is a small window on the web.

Madobe is a WebKit browser with three things Safari does not do.

**Float (Mac).** Shift-Command-F pops the current tab into a small window that stays above every other app on every Space and never takes focus. Slide it see-through, turn on click-through so your mouse passes straight to what is underneath, and get back with Option-Command-F or the Madobe icon in the menu bar. It remembers its size and place.

**Pair (iPhone and iPad).** Two pages in one window, side by side on iPad and in landscape, stacked in portrait. Each has its own address bar and back and forward, with a swap button and a divider you drag.

**Site rules (both).** Per-site page zoom, dark appearance, block images, block scripts and block pop-ups, kept on the device and applied through WebKit.

There are also tabs, private tabs, bookmarks, history, find in page, tracker blocking and a Shortcuts action, Open in Madobe (and Open in Float Window on the Mac). Nothing is sent anywhere.

<img src="progress.svg" width="460">

## Architecture

<img src="architecture.svg" width="600" alt="">

## Run

```
cd ios && xcodegen && open Madobe.xcodeproj
```

## License

MIT
