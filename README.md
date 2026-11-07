# Soulection Radio (Unofficial)

An unofficial iPhone and iPad app for [Soulection Radio](https://radio.soulection.com/). It's the same site you'd open in Safari, as a real app on your home screen: it keeps playing with the screen off and adds likes, listening history, playlists, a sleep timer, a random show button and an endless Mixtape.

> **Unofficial fan project.** Not affiliated with, endorsed by or connected to Soulection. The app shows the official site; all shows, music, names and artwork belong to Soulection and the artists. No ads, accounts or tracking.

## Download

**[Download Soulection Radio](https://github.com/hotwheelz3000/soulection-app/releases/latest)**: open the link, then tap the `.ipa` file under **Assets** (named with the version and build, e.g. `SoulectionRadio-5.0-12.ipa`; the first build of a version has no build number).

The link always has the newest build. Each build has its own file name, so downloads never clash.

## How to install

The app isn't on the App Store, so you install it yourself (iOS 17 or later):

1. **Download the `.ipa`** from the link above.
2. **Install it** with [Sideloadly](https://sideloadly.io) (Mac or Windows), [AltStore](https://altstore.io) or a signing service such as Signulous.
3. **Trust it:** Settings → General → VPN & Device Management → your Apple ID → **Trust**. If iOS asks, turn on **Developer Mode** in Settings → Privacy & Security and restart.

With a free Apple ID the app stops opening after 7 days; install it again the same way. Your likes and history stay.

## What it does

**Listening**
- **Plays with the screen off,** and doesn't stop other audio when you open it.
- **Lock screen and Dynamic Island** show the song, artist and cover; next / previous jump between songs in the show.
- **Big player:** tap the player at the bottom, or swipe it up (from the player or its tab). Big artwork, a draggable progress bar, previous / play / next, a heart, the sleep timer and AirPlay. **Playing from** opens the show's page. Swipe down to close; if it's open when you leave the app, it's still open when you come back.
- **Up Next:** the songs coming up (in Likes, History or Mixtape) or the show's songs. Tap one to play it, or its heart to like it.
- **Swipe to skip:** swipe the mini player left for the next song, right for the one before. (VoiceOver gets Previous / Next buttons.) The back button in the big player restarts the song first, like Spotify.
- **Starting a show:** the Soulection logo spins in the play button until the sound starts.
- **The playing song is marked** in a show's tracklist with small moving bars.
- **Smooth switches between shows:** with the app open, the volume dips at the end of a song and comes back up on the next one.
- **Phone calls:** the music pauses for a call and comes back after.
- **Works on iPad.**

**Likes and History**
- **Heart any song** in a tracklist or either player. Likes are kept in the app.
- **Likes and History** (the heart at the top): search, swipe left to remove, tap a cover to open its show at that song.
- **⋯ More:** share a song, or open it on Spotify or Apple Music.
- **Play them as a playlist:** **Play in order**, **Shuffle**, or tap a song to start there, across shows and with the screen off.
- **Continue listening:** at the top of History, the shows you were in the middle of. Tap one to pick it back up where you left off.
- **History** keeps your last 500 songs; **Clear** asks twice and offers to export first.

**Extras**
- **Random show:** the dice plays a random show from the start, right where you are.
- **Mixtape:** endless random songs, each from a different show. Each one goes into Likes and History; remove any you don't want.
- **Sleep timer:** 5, 15 or 30 minutes, 1 hour, end of song, end of show or your own time, with **+5 min** while it runs. The music fades out, even with the screen off.
- **New show notifications,** plus a **NEW** label on new shows until you open them. For alerts while the app is closed, keep Background App Refresh on and don't swipe the app away (iOS decides when it checks).
- **Welcome player:** "This is Soulection Radio." Its play button starts the newest show.
- **Top bar** on every page: Back and Home on the left; Likes, dice, Mixtape, sleep timer and Help (**?**) on the right. Press and hold an icon for its name.

**Backup**
- **On this iPhone, always:** `Soulection Radio Backup.json` in Files → **On My iPhone → Soulection**, updated after every change. Nothing to set up; it survives updates but not deleting the app.
- **iCloud Drive (turn it on once):** in Likes, tap **Turn on** → **Save a backup file**, pick a folder in iCloud Drive and tap **Save**. That file is kept up to date and survives deleting the app or switching phones.
- **If the iCloud copy pauses,** you'll get a reminder at most once a week: tap **Reconnect**, pick the file, then save it back to the same folder (**Save**, then **Replace**; Replace just updates it). Or tap **New backup**.
- **After a reinstall,** tap **Pick my backup file** when the app asks. Your songs come back and backup carries on.
- **Export / Import** for one-off copies.

**Accessibility**
- The app's own screens aim for **WCAG 2.2 AA**: 4.5:1 contrast, VoiceOver labels, a tap alternative for every swipe, and full keyboard use (Escape closes panels).
- **Reduce Motion** turns off the app's animations. VoiceOver announces song changes and messages.

## Known limits

- **It depends on Soulection's website.** If the site changes, extras like song names, hearts or playlists may break until the app is updated. Playback keeps working.
- **Shows without song times:** some older shows list every song at 00:00:00, so the app can't tell which song is playing in them.
- **Screen-off switching** (Likes, History, Mixtape) loads the next show ahead and switches a moment early, so a song's last second or two may be cut.
- **Free Apple ID:** reinstall every 7 days.

## Feedback

Found a bug or have an idea? [Open an issue](https://github.com/hotwheelz3000/soulection-app/issues) with the version from the bottom of the help window (**?**). A screenshot or screen recording helps a lot.

## How it was made

I'm a beginner developer. I built this by describing what I wanted to Claude Code, testing each build on my iPhone and sending back screenshots and recordings of anything that felt off. I never wrote the code by hand or opened Xcode.

- **No Xcode, no Mac of my own.** The app is a Swift package built with [xtool](https://xtool.sh). Every push to `main` runs a GitHub Actions workflow on a macOS runner that builds an unsigned `.ipa` and publishes it as the latest release.
- **A web view plus injected JavaScript.** The app loads the real site in a `WKWebView`. Lock-screen info runs both on the page (working out the song from the tracklist) and inside the SoundCloud player frame. Switching shows works like a relay: the next show starts muted next to the current one and takes over, so the sound never stops and iOS keeps the app running.
- **Native where it matters.** Likes, history, backups and the sleep timer run in Swift, so they survive the website's data being cleared and keep working with the screen locked.
- **Tested before the phone.** Each feature was checked in headless Chromium against a mock of the site (with an axe-core accessibility check), then on the iPhone.

## For developers

- **Code** (`Sources/SoulectionRadio/`):
  - `FavoritesScript.swift`: the injected JavaScript for hearts, Likes/History, playlists and the player relay, both players, Up Next, the sleep timer, dice, Mixtape, Continue listening, help and the welcome screen.
  - `NowPlayingScript.swift`: lock-screen info and track buttons, on the page and inside the player frames.
  - `Favorites.swift`: storage for likes and history, backups (on the iPhone and iCloud Drive), Export/Import, the sleep timer, the volume dip, AirPlay, sharing and Spotify/Apple Music links.
  - `WebView.swift`: the web view and its layout fixes. `NewShows.swift`: new-show notifications. `SoulectionRadioApp.swift`: audio setup. `ContentView.swift` / `PageAppearance.swift`: the screen and background color. `BuildInfo.swift`: the version shown in Help (written by the workflow).
- **Settings:** `xtool.yml` (name, bundle ID, icon) and `SoulectionRadio-Info.plist` (home screen name, version, background audio, file sharing). Icon: `Resources/AppIcon.png`.
- **Releases:** the title uses `CFBundleShortVersionString`, and the notes come from `RELEASE_NOTES.md`. Change both for a new version.
- **Build:** pushes to `main` build automatically, or run `xtool dev build --ipa` locally. `./rename-app.sh <AppName> <bundle.id>` renames the app.
- **Claude Code skills** in `.claude/skills/`: xtool notes plus review, CI and documentation-audit helpers.
