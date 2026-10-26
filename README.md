# Soulection Radio

An iPhone app for [Soulection Radio](https://radio.soulection.com/). It's the same site you'd open in Safari, but as a real app on your home screen that keeps playing in the background.

## What it does

- **Keeps the music going.** Lock your phone or switch apps and the show keeps playing.
- **Shows the song that's on.** Your lock screen and Control Center show the current song, artist and show cover, and they update as the tracks change.
- **Skip between songs.** The next and previous buttons on your lock screen jump to the next or previous song in the show's tracklist. Tap previous once to restart a song, or twice to go back one.
- **Save your favorite songs.** Tap the heart next to any song in a show's tracklist, or the heart in the player at the bottom for the song that's playing. Tap it again to remove it. Your favorites are saved in the app, so clearing the website's data won't lose them.
- **Your favorites, in one place.** Swipe up on the player at the bottom (or on the small Favorites tab when nothing is playing) to see them, newest first. Swipe a song left to remove it. Swipe down or tap outside to close.
- **Play your favorites as a playlist.** Tap **Play in order** or **Shuffle**, or tap a song to start from there. Each song plays from its spot in the show, then the next favorite starts, even if it's in a different show. Your lock screen shows the song, and next and previous move through your favorites. Tap a song in a show yourself to go back to normal listening.
- **Feels like the website.** Full screen, same look, same episodes and search.
- **Works with your speakers.** AirPlay to your TV or speakers is supported.

## How to install

The app isn't on the App Store, so you install it yourself. It takes a few minutes.

1. **Download the app file.** Open the [Actions page](https://github.com/hotwheelz3000/soulection-app/actions), tap the newest **Build IPA** run with a green check, scroll to **Artifacts** and download **SoulectionRadio-ipa**. Unzip it to get `SoulectionRadio.ipa`.
2. **Install it with a sideloading app** such as [Sideloadly](https://sideloadly.io) or [AltStore](https://altstore.io). Sign in with your Apple ID when it asks.
3. **Trust it on your iPhone.** Go to **Settings → General → VPN & Device Management**, tap your Apple ID, then **Trust**. If iOS asks, turn on **Developer Mode** in **Settings → Privacy & Security** and restart.

With a free Apple ID, the app stops opening after 7 days. Just install it again the same way.

## Tips

- **Updating:** download the newest file and install it over the old one.
- **New icon not showing?** Delete the app first, then install the new version.
- **Song name not changing on the lock screen?** Playback still works. Soulection may have changed their site, so the song info needs an update.

## For developers

Built with [xtool](https://xtool.sh), so there's no Xcode project. Every push to `main` builds a fresh, unsigned app file on GitHub Actions.

- App code is in `Sources/SoulectionRadio/`. The lock-screen song info lives in `NowPlayingScript.swift`. Favorites live in `FavoritesScript.swift` (hearts, the Favorites sheet and the playlist) and `Favorites.swift` (saving them in the app).
- The icon is `Resources/AppIcon.png`. Replace it and push to change it.
- App settings (name, bundle ID, icon) are in `xtool.yml`.
- To build locally with xtool installed: `xtool dev build --ipa`.

Made from the `my-ios-app` template.
