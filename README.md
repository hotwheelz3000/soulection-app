# Soulection Radio

A full-screen iOS app for [radio.soulection.com](https://radio.soulection.com/), built Xcode-free with [xtool](https://xtool.sh). It looks and behaves like the Safari home-screen web app, plus reliable background audio and a lock screen that follows each song.

## Features

- **Background audio:** keeps playing with the screen locked or the app in the background (`UIBackgroundModes: audio` in `SoulectionRadio-Info.plist`, `AVAudioSession` `.playback` category in `SoulectionRadioApp.swift`).
- **Edge to edge:** the web view fills the whole screen and the page handles safe areas with CSS `env(safe-area-inset-*)`. `viewport-fit=cover` is injected if the page lacks it.
- **Lock screen / Now Playing follows the current song:** title, artist, show name and episode cover update as the tracklist moves. Next/previous track jump between tracklist timestamps (previous restarts the current song unless you're under 3 seconds in). Playback runs inside an embedded SoundCloud player, so the script runs in both the Soulection page and that player.
- **Browsing:** pull to refresh, swipe back/forward, and links that leave `soulection.com` open in Safari.
- **Playback extras:** inline media playback with no tap required, AirPlay and Picture in Picture.

## Files

| Path | What it does |
| --- | --- |
| `Sources/SoulectionRadio/SoulectionRadioApp.swift` | App entry point, audio session setup |
| `Sources/SoulectionRadio/ContentView.swift` | Root view |
| `Sources/SoulectionRadio/WebView.swift` | WKWebView wrapper: edge to edge, refresh, gestures, external links |
| `Sources/SoulectionRadio/NowPlayingScript.swift` | Injected script that drives lock-screen song info and track buttons |
| `Sources/SoulectionRadio/PageAppearance.swift` | Remembers the page background color between launches |
| `SoulectionRadio-Info.plist` | Background audio mode (`infoPath` in `xtool.yml`) |
| `xtool.yml` | App name, bundle ID, icon and Info.plist paths |
| `Resources/AppIcon.png` | App icon |
| `scripts/fetch-app-icon.py` | Fallback: builds an icon from the site's favicon if `AppIcon.png` is missing |
| `.github/workflows/build-ipa.yml` | Builds the unsigned IPA on every push to `main` |

## App icon

The icon is the chrome Soulection eye on black, at `Resources/AppIcon.png` (1024×1024 PNG, no transparency). To change it, replace that file and push. If the file is ever deleted, the build workflow runs `scripts/fetch-app-icon.py` to generate one from the site's favicon and commits it.

After installing a build with a new icon, delete the old app first so iOS doesn't keep the cached icon.

## Download the IPA

1. Open the repo's **Actions** tab and pick the latest **Build IPA** run. To build without pushing, choose **Build IPA → Run workflow**.
2. At the bottom of the run page, under **Artifacts**, download **SoulectionRadio-ipa**. It's a zip containing `SoulectionRadio.ipa`.

The IPA is **unsigned**. Sign it when installing, for example with `xtool install` after `xtool auth login`, or with Sideloadly or AltStore. GitHub keeps artifacts for 90 days.

## Build locally

With xtool installed ([macOS](https://xtool.sh/documentation/xtooldocs/installation-macos), [Linux/Windows](https://xtool.sh/documentation/xtooldocs/installation-linux)):

```bash
xtool dev build --ipa   # unsigned IPA at xtool/SoulectionRadio.ipa
xtool dev               # build, sign and run on a connected device
```

## Notes

- Made from the `my-ios-app` template, renamed with `./rename-app.sh SoulectionRadio com.hotwheelz3000.SoulectionRadio`.
- The Now Playing script depends on the site's current markup (tracklist rows and the bottom player). If Soulection redesigns the site, the lock-screen song info may stop updating while playback keeps working.
- `.claude/skills/using-xtool/` holds xtool reference notes for Claude Code sessions.
