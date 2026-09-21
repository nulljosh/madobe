SEO gap not fixed: og:image is missing. Normally generated from the first gallery screenshot, but there is no gallery to generate it from (see gallery note below), so no og:image was added rather than fabricating one. Add a real 1200x630 og.png once screenshots exist.

Gallery: skipped. Lucarne has no screenshots folder anywhere in the repo, and generating one would require opening a browser to capture the app or landing page, which this run isn't allowed to do. No gallery images were fabricated. If screenshots get added later, rebuild launch/gallery/ from them.

What Joshua still does by hand:
- Product Hunt: create the post at producthunt.com/posts/new using launch/producthunt.md, upload real screenshots once they exist (currently none), pick a hunter, pick launch day.
- Hacker News: submit launch/hn.md manually at news.ycombinator.com/submit. Has a real technical hook (thin WebKit wrapper, one resolve() function, single-file architecture across three platforms), worth posting.
- Reddit: post each file in launch/reddit/ by hand, one subreddit at a time, spaced out. Check account karma/age on r/privacy and r/degoogle first, and check for pinned self-promo threads on r/macapps and r/iOSProgramming before posting standalone.
- X: post the thread in launch/x.md from the real account.

App Store listing (read-only check, nothing changed):
- Subtitle present: "A browser with nothing else".
- Promotional text present: "An address bar and a WebKit view. Nothing else until there is a reason."
- Description, keywords present in metadata/version/1.0.0/en-US.json.
- Both existing versions (1.0.0 iOS and 1.0.0 macOS) show appStoreState REJECTED in ASC. Nothing is live on the App Store right now, only on the web. Not fixed here, this needs Joshua to resubmit a version before any PH/HN traffic can convert to an App Store install.
