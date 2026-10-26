# iOS app template (xtool)

A starting point for SwiftUI iOS apps built with [xtool](https://xtool.sh): SwiftPM instead of an Xcode project, and a GitHub Actions workflow that builds an unsigned `.ipa` on every push to `main`.

What's here:

- `Package.swift`, `xtool.yml`, `Sources/MyApp/`: a placeholder "Hello, world!" SwiftUI app, so the template builds as-is.
- `rename-app.sh`: renames the placeholder to your app.
- `.github/workflows/build-ipa.yml`: builds the `.ipa` on macOS and uploads it.
- `.claude/skills/using-xtool/`: a Claude Code skill with xtool reference notes.

## Start a new app

1. On GitHub, click **Use this template → Create a new repository** (or clone this repo and push it to a new one).
2. Clone your new repo and rename the app (below).
3. Commit and push to `main`. The workflow builds your IPA.

## Rename the app

```bash
./rename-app.sh CoffeeLog com.yourname.CoffeeLog
```

The first argument is the app name. It becomes a Swift module and type name, so use letters, digits and `_` only (no spaces or hyphens). The second is the bundle ID.

The script updates the names in `Package.swift`, sets `product:` and `bundleID:` in `xtool.yml`, renames `Sources/MyApp/` and `MyAppApp.swift`, and renames the `MyAppApp` struct. Run it again any time to rename once more.

## Download the IPA

1. Open the repo's **Actions** tab and pick the latest **Build IPA** run. To build without pushing, choose **Build IPA → Run workflow**.
2. At the bottom of the run page, under **Artifacts**, download **`<AppName>-ipa`**. It's a zip containing `<AppName>.ipa`.

The workflow reads the app name from `product:` in `xtool.yml`, so the file is named after your app. GitHub keeps artifacts for 90 days by default.

The IPA is **unsigned**, so an iPhone won't install it directly. Sign it when installing, for example with `xtool install` after `xtool auth login`, or with a sideloading tool such as Sideloadly or AltStore.

## Build locally

With xtool installed ([macOS](https://xtool.sh/documentation/xtooldocs/installation-macos), [Linux/Windows](https://xtool.sh/documentation/xtooldocs/installation-linux)):

```bash
xtool dev build --ipa   # unsigned IPA at xtool/<AppName>.ipa
xtool dev               # build, sign and run on a connected device
```
