# Soulection Radio (Unofficial)

An unofficial iPhone and iPad app for [Soulection Radio](https://radio.soulection.com/). It's the same site you'd open in Safari, but as a real app on your home screen. It keeps playing with the screen off and adds the extras I always wanted: likes, listening history, playlists, a sleep timer, a random show button and an endless Mixtape.

> **Unofficial fan project.** Not affiliated with, endorsed by or connected to Soulection. The app shows the official site; all shows, music, names and artwork belong to Soulection and the artists. There are no ads, accounts or tracking.

## Download

**[Download the latest SoulectionRadio.ipa](https://github.com/hotwheelz3000/soulection-app/releases/latest/download/SoulectionRadio.ipa)** · [all releases](https://github.com/hotwheelz3000/soulection-app/releases)

Every change to the app is built automatically and published there, usually within a few minutes. Each release also has a copy named with its build time (for example `SoulectionRadio-2026-10-26-1541.ipa`); download that one on an iPhone so a new build never gets saved as "SoulectionRadio.ipa 2".

## How to install

The app isn't on the App Store, so you install it yourself with your own Apple ID. It takes a few minutes. You need iOS 17 or later.

1. **Download `SoulectionRadio.ipa`** from the link above.
2. **Install it with a sideloading app** such as [Sideloadly](https://sideloadly.io) (Mac or Windows) or [AltStore](https://altstore.io). Sign in with your Apple ID when it asks.
3. **Trust it on your iPhone.** Go to **Settings → General → VPN & Device Management**, tap your Apple ID, then **Trust**. If iOS asks, turn on **Developer Mode** in **Settings → Privacy & Security** and restart.

With a free Apple ID, the app stops opening after 7 days. Install it again the same way; your likes and history stay.

## What it does

**Listening**
- **Keeps playing with the screen off,** and doesn't stop a podcast or music that's already playing when you open it.
- **Lock screen and Dynamic Island** show the current song, artist and show cover, and update as the songs change. Next and previous jump between songs in the show's tracklist.
- **Full-size player.** Tap or swipe up on the player at the bottom: big artwork, the song, a progress bar you can drag, previous / play / next, a heart, the sleep timer and AirPlay. Tap **Playing from** to open that show's tracklist.
- **The playing song is marked** in a show's tracklist with small moving bars next to its heart.
- **Phone calls:** the music pauses for a call and starts again when the call ends or you decline it.
- **Works on iPad,** with the player at the bottom spanning the full width.

**Likes and History**
- **Heart any song** in a show's tracklist or in the player. Your likes are kept in the app, not the website.
- **Your Likes, in one place:** tap the heart at the top. Search them with the box at the top. Swipe a song left to remove it (or use its **⋯** button). Tap a song's cover to open its show at that song.
- **⋯ More:** on any song in Likes or History, and in the full player: share it, or find it on Spotify or Apple Music.
- **Play them as a playlist:** **Play in order** (top to bottom, like the list) or **Shuffle**, or tap a song to start there. Each song plays from its spot in its show, then the next one starts, even from a different show, including with the screen off.
- **Listening history:** every song you play is saved the moment it starts (the show's intro isn't counted). Open it from the same panel (**History**). It keeps your last 500 songs; **Clear** asks twice and offers to export first.

**Extras**
- **Random show:** the dice starts a random episode from the very beginning.
- **Mixtape:** the cassette plays endless random songs from random shows. Each song is added to your Likes as soon as it's picked (even if you skip it) and to History once it plays; remove any you don't want.
- **Sleep timer:** the zZZ at the top (or in the full player). 5, 15 or 30 minutes, 1 hour, end of song, end of show, or your own time. While a timer runs, **Add 5 more minutes** extends it. The music fades out and pauses, even with the screen off.
- **New show notifications:** when a new show is posted you get "New show: Soulection Radio #751 · Tap to listen", and the newest show gets a **NEW** label until you open it. The app asks once if it can send notifications. iOS decides when the background check runs (usually within a few hours of a new show), and it doesn't run if you swipe the app away.
- **Pick up where you left off:** when you open the app, it offers to carry on from the show and spot you were last listening to.
- **Help:** a welcome screen explains each button when you open the app (tick **Don't show again** to hide it). Tap **?** at the top any time, or press and hold a top-bar icon for its name. The bottom of the help window shows which build you have.

**Accessibility**
- The app's own features (Likes, History, the players, the sleep timer, help and messages) aim to meet **WCAG 2.2 AA**: text contrast of at least 4.5:1, labels for VoiceOver, a tap alternative for every swipe, and full keyboard use (Tab, Enter or Space, Escape closes panels).
- **Reduce Motion** (iPhone Settings → Accessibility → Motion) turns off the app's animations.
- VoiceOver announces song changes and messages. Messages stay on screen long enough to read.
- Soulection's own pages (tracklists, search) are theirs; the app raises their grey text to the same contrast but can't change the rest.

**Backup to iCloud Drive**
- **Turn it on:** in Likes, tap **Turn on** next to Auto-backup, then **Create one**. Pick a folder in iCloud Drive (for example "Soulection") and tap **Save** (and **Replace** if a backup is already there). From then on, `Soulection Radio Backup.json` is updated every time your Likes or History change. It lives outside the app, so it survives deleting the app or switching phones.
- **After a reinstall:** the app offers to restore. Tap **Pick backup file**, choose `Soulection Radio Backup.json`, then save it back to the same folder (**Save**, then **Replace**) so auto-backup keeps going.
- **Manual backups:** **Export** saves a one-off copy anywhere; **Import** adds one back. If auto-backup is off (or failing), the app reminds you every 4 new likes.

## Known limits

- **It depends on Soulection's website.** The app adds its features on top of radio.soulection.com. If the site changes, things like song names on the lock screen, hearts or playlists may stop working until the app is updated. Playback itself keeps working.
- **Screen-off switching between shows** (Likes, History, Mixtape) loads the next show a little ahead of time. On a slow connection you may hear a few seconds of the old show before the next song starts.
- **Free Apple ID:** reinstall every 7 days (see above).

## Feedback

Found a bug or have an idea? [Open an issue](https://github.com/hotwheelz3000/soulection-app/issues) and include the build shown at the bottom of the help window (**?**). A screenshot or screen recording helps a lot.

## How it was made

I'm a beginner developer. I built this by describing what I wanted to Claude Code, testing each build on my iPhone, and sending back screenshots and screen recordings of anything that looked or felt off. I didn't write the code by hand and never opened Xcode.

- **No Xcode app, no Mac of my own.** The app is a Swift package built with [xtool](https://xtool.sh) (it uses the iOS SDK that comes with the build server's Xcode, but nobody opens Xcode). Every push to `main` runs a GitHub Actions workflow on a macOS runner that builds an unsigned `.ipa` and publishes it as the latest release.
- **A web view, plus a lot of glue.** The app loads the real site in a `WKWebView` and adds features with injected JavaScript:
  - The site plays audio through an embedded SoundCloud player on another domain, so lock-screen info runs in two places: the Soulection page works out the current song from the tracklist, and a script inside the player frame sets the lock screen and track buttons.
  - Switching shows with the screen off works like a relay: the next show is loaded ahead in a hidden player and takes over the moment the current song ends, so the sound never stops and iOS keeps the app running.
  - Likes, history, backups and the sleep timer's fixed times are stored and run natively in Swift, so they survive website data being cleared and keep working with the screen locked.
  - The page-side scripts wait for the site's React app to finish loading before touching it.
- **Testing without a phone in the loop.** Each feature was checked first in headless Chromium against a mock page copying the site's real markup (plus an automated WCAG check with axe-core), then on the iPhone. The test pages aren't part of this repo.

## For developers

- **Code:** `Sources/SoulectionRadio/`
  - `WebView.swift`: the web view, edge-to-edge layout and safe-area fixes for the site's top bar and bottom player.
  - `NowPlayingScript.swift`: lock-screen song info, track buttons and remote play/pause, both on the page and inside the SoundCloud player frames.
  - `FavoritesScript.swift`: hearts, the Likes/History panel, playlists and the background relay between players, listening history, the full-size player, the mini player, the sleep timer, the dice, Mixtape, help and the welcome screen.
  - `Favorites.swift`: saves likes and history in the app, auto-backup to iCloud Drive and restore, Export/Import, the sleep timer's countdown and fade, AirPlay, and resuming after phone calls.
  - `SoulectionRadioApp.swift`: background audio setup, without interrupting other apps at launch.
  - `BuildInfo.swift`: the build label shown in the help window (written by the workflow).
  - `ContentView.swift` and `PageAppearance.swift`: the screen that holds the web view, and matching the page's background color.
- **Icon:** `Resources/AppIcon.png` (`scripts/fetch-app-icon.py` can fetch one from the site).
- **App settings:** `xtool.yml` (build name, bundle ID, icon) and `SoulectionRadio-Info.plist` (home screen name "Soulection", background audio, dark mode).
- **Renaming:** `rename-app.sh` renames the app's build product.
- **Build:** pushes to `main` build automatically. To build locally with xtool installed: `xtool dev build --ipa`.
- **Claude Code skills** in `.claude/skills/`: xtool reference notes, plus review, CI and documentation-audit helpers.
