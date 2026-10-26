# Soulection Radio

An iPhone app for [Soulection Radio](https://radio.soulection.com/). It's the same site you'd open in Safari, but as a real app on your home screen that keeps playing in the background, with the extras I always wanted: favorites, listening history, a sleep timer and a random show button.

> Unofficial fan project. Not affiliated with or endorsed by Soulection. The app shows the official site; all shows, music and artwork belong to Soulection and the artists.

## What it does

- **Easy to learn.** A welcome screen explains each button when you open the app (tick **Don't show again** to hide it). Later, tap the **?** in the top bar to see it again, or press and hold any top bar icon to see its name.
- **Keeps the music going.** Lock your phone or switch apps and the show keeps playing.
- **Doesn't interrupt you.** Opening the app won't stop a podcast or music that's already playing. It only takes over when you press play on a show.
- **Full-size player.** Tap or swipe up on the player at the bottom for a full-screen player like Spotify's. It follows your finger, and the cover art grows out of the mini player's thumbnail. Inside: big cover art, the song and artist, a progress bar you can drag, large previous, play/pause and next buttons (they jump between songs in the tracklist), a heart for the current song, the sleep timer and AirPlay. Swipe down to close.
- **Quick play and pause.** Play/pause goes straight to the audio, so it reacts right away.
- **Works on iPad too.** The player at the bottom spans the full width, like on iPhone.
- **Shows the song that's on.** Your lock screen and Control Center show the current song, artist and show cover, and they update as the tracks change.
- **Skip between songs.** The next and previous buttons on your lock screen jump to the next or previous song in the show's tracklist. Tap previous once to restart a song, or twice to go back one.
- **Save your favorite songs.** Tap the heart next to any song in a show's tracklist, or the heart in the player at the bottom for the song that's playing. Tap it again to remove it. Your favorites are saved in the app, so clearing the website's data won't lose them.
- **Your favorites, in one place.** Tap the heart next to the search box at the top to see them, newest first. Swipe a song left to remove it. Swipe down or tap outside to close.
- **Play your favorites as a playlist.** Tap **Play in order** or **Shuffle**, or tap a song to start from there. Each song plays from its spot in the show, then the next favorite starts, even if it's in a different show. Your lock screen shows the song, and next and previous move through your favorites. Tap a song in a show yourself to go back to normal listening.
- **Listening history.** Every song you play is saved in the app the moment it starts (from its timestamp, so a show's intro isn't counted), newest first, like Spotify's Recently played. Open it from the same panel as Favorites (tap **History** at the top). Each song shows when you heard it. Tap one to play it from its spot, use **Play in order** or **Shuffle**, tap the heart to add it to favorites, swipe left to remove it, or tap **Clear** to empty the list (it asks twice, and offers to export a backup first). It keeps your last 500 songs.
- **Sleep timer.** Tap the zZZ in the top bar (or in the full-size player) and pick 5, 15 or 30 minutes, 1 hour, **End of song**, **End of show**, or your own time with the − and + buttons. While it's on, the zZZ lights up in a slow wave (tap it to see a big countdown), and when time's up the music fades out and pauses, even with your phone locked. The fade gently lowers your phone's volume, then puts it back after pausing. Tap the zZZ again to turn it off. It also works in Mixtape and playlists: End of song and End of show stop after the current song.
- **Random show.** Tap the dice next to the search box to start a random episode from the very beginning.
- **Mixtape.** Tap the cassette for endless random songs from random shows. Each song is added to your Likes and History, even if you skip it. Remove any you don't want. Next skips to another song, and it keeps going with your phone locked. Tap the cassette again to stop.
- **Automatic backup to iCloud Drive.** In the Favorites or History panel, tap **Turn on** next to Auto-backup:
  - **Use my backup file** if you already have `Soulection Radio Backup.json`: pick it, and the app keeps it up to date.
  - **Create one** if you don't: "Save to Files" opens, pick a folder in iCloud Drive (for example "Soulection") and tap **Save**, then tap the file you just saved. That second tap is what lets the app keep updating it.
  From then on the file is updated every time your Likes or History change. It lives outside the app, so it survives deleting the app or losing your phone.
- **Restoring after a reinstall.** When you open a fresh install, the app offers to restore: tap **Pick backup file** and choose `Soulection Radio Backup.json`. Everything comes back and auto-backup keeps going with that same file.
- **Manual backups.** **Export** saves a one-off backup file anywhere you like, and **Import** brings one back. Imported songs are added to the ones you already have. If auto-backup is off, the app reminds you every 4 new favorites.
- **Feels like the website.** Full screen, edge to edge, same look, same episodes and search. Everything the app adds uses the site's own colors and fonts.
- **Works with your speakers.** AirPlay to your TV or speakers is supported.

## How to install

The app isn't on the App Store, so you install it yourself. It takes a few minutes.

1. **Download the app file.** Open the [Actions page](https://github.com/hotwheelz3000/soulection-app/actions), tap the newest **Build IPA** run with a green check, scroll to **Artifacts** and download **SoulectionRadio-ipa**. Unzip it to get `SoulectionRadio.ipa`.
2. **Install it with a sideloading app** such as [Sideloadly](https://sideloadly.io) or [AltStore](https://altstore.io). Sign in with your Apple ID when it asks.
3. **Trust it on your iPhone.** Go to **Settings → General → VPN & Device Management**, tap your Apple ID, then **Trust**. If iOS asks, turn on **Developer Mode** in **Settings → Privacy & Security** and restart.

With a free Apple ID, the app stops opening after 7 days. Just install it again the same way.

## Tips

- **Updating:** download the newest file and install it over the old one. Your favorites and history stay.
- **New icon not showing?** Delete the app first, then install the new version. With auto-backup on, pick your backup file when the app offers to restore and everything comes back.
- **Song name not changing on the lock screen?** Playback still works. Soulection may have changed their site, so the song info needs an update.

## How it was made

I'm a beginner developer, and this was built in one night by describing what I wanted to Claude Code, testing each build on my iPhone, and sending back screenshots of what looked off. I didn't write the code by hand and never opened Xcode.

- **No Xcode, no Mac needed to build.** The app is a Swift package built with [xtool](https://xtool.sh). Every push to `main` runs a GitHub Actions workflow on a macOS runner that builds an unsigned `.ipa`, so a new version is ready to download a few minutes after each change.
- **Started from a template.** I first made [my-ios-app](https://github.com/hotwheelz3000/my-ios-app), a reusable template with the xtool setup, the build workflow and a rename script. Each new app is "Use this template", rename, describe the app.
- **A web view, plus a lot of glue.** The app loads the real site in a `WKWebView` and adds features with injected JavaScript:
  - The site plays audio through an embedded SoundCloud player on another domain, so the lock-screen song info runs in two places: the Soulection page works out the current song from the tracklist, and a script inside the player frame sets the lock screen and track buttons.
  - Favorites, history and the sleep timer's fixed times are stored and run natively in Swift, so they survive website data being cleared and keep working with the screen locked.
  - The page-side scripts wait for the site's React app to finish loading before touching it, so the site doesn't throw away the added buttons.
- **Iterating on feel.** Most of the night went to small things only visible on a real phone: times cut off by the rounded corners, the top bar hiding under the clock, hearts too small, an orange accent that didn't fit, a floating tab that felt wrong, and a sleep timer icon copied from a screen recording of another app.
- **Testing without a phone in the loop.** Each feature was checked first in headless Chromium against a mock page copying the site's real markup, then on the iPhone.

## For developers

- **Code:** `Sources/SoulectionRadio/`
  - `WebView.swift`: the web view, edge-to-edge layout and safe-area fixes for the site's top bar and bottom player.
  - `NowPlayingScript.swift`: lock-screen song info and next/previous track buttons.
  - `FavoritesScript.swift`: hearts, the Favorites/History panel, playlists, listening history, the full-size player, quick play/pause, the sleep timer, the dice, Mixtape and the backup reminder.
  - `Favorites.swift`: saves favorites and history in the app, auto-backup to a file in iCloud Drive and restore, Export/Import, the sleep timer's countdown and fade, and the AirPlay picker.
  - `SoulectionRadioApp.swift`: background audio setup, without interrupting other apps at launch.
- **Icon:** `Resources/AppIcon.png`. Replace it and push to change it.
- **App settings** (name, bundle ID, icon, Info.plist): `xtool.yml`.
- **Build:** pushes to `main` build automatically. To build locally with xtool installed: `xtool dev build --ipa`.
- **Claude Code skills** in `.claude/skills/`: xtool reference notes, plus review and CI helpers.
