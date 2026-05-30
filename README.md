<p align="center">
  <img src="social.png" alt="Similar Photos" />
</p>

<p align="center">
  Find visually similar photos in your iPhone library using Apple's Vision framework.<br>
  Paste an image from clipboard or pick from your library — the app searches your entire photo collection and shows the closest visual matches.
</p>

## Features

- **Indexed search** — builds a visual fingerprint of every photo once, then searches instantly
- **Paste from clipboard** — copy an image from Messages/Safari/anywhere, paste to search
- **Similarity scores** — each result shows a percentage match (green/orange/red)
- **Reject noise** — long-press a bad result to remove it and similar junk
- **Photo details** — tap a result to see the full image with date taken and GPS location
- **Load more** — keep loading results beyond the initial 30
- **Shortcuts integration** — use "Find Similar Photos" as a Shortcuts action

## Install on iPhone

### Option A: AltStore PAL (EU only — no 7-day limit)

1. **Install AltStore PAL** on your iPhone (requires iOS 18.0+, EU or Japan):
   - Go to [altstore.io/download](https://altstore.io/download) in Safari on your iPhone
   - Tap **Download** — a "Marketplace Installation" alert will appear
   - Open **Settings** → tap **Allow Marketplace From AltStore LLC** (at the top under your Apple ID)
   - Return to the page, tap **Download** again → select **Install App Marketplace**

2. **Add the Similar Photos source:**
   - Open AltStore PAL
   - Go to **Sources** (or **Browse**)
   - Tap **Add Source**
   - Paste this URL:
     ```
     https://raw.githubusercontent.com/Rozkalns/SimilarPhotos/main/altstore-source.json
     ```

3. **Install the app:**
   - Find "Similar Photos" in the source
   - Tap **Install**
   - Open the app, grant photo library access when prompted
   - Wait for initial indexing (takes a few minutes depending on library size)

### Option B: AltStore Classic (worldwide — 7-day re-sign)

1. **Install AltStore** on your computer and iPhone:
   - Download AltServer from [altstore.io](https://altstore.io) on your Mac or PC
   - Run AltServer, connect your iPhone via USB
   - Install AltStore to your iPhone through AltServer

2. **Download the IPA:**
   - Go to [Releases](https://github.com/Rozkalns/SimilarPhotos/releases/latest)
   - Download `SimilarPhotos.ipa` to your phone

3. **Install via AltStore:**
   - Open AltStore on your iPhone
   - Go to **My Apps** → tap the **+** button
   - Select the downloaded `SimilarPhotos.ipa`
   - The app installs and is signed with your Apple ID

4. **Important:** AltStore Classic apps expire every 7 days. Keep AltServer running on your computer and connect to the same WiFi as your iPhone to auto-refresh.

### Option C: Build from source (any region, requires Mac)

1. Install [Xcode](https://apps.apple.com/app/xcode/id497799835) (free) from the Mac App Store
2. Clone this repo:
   ```
   git clone https://github.com/Rozkalns/SimilarPhotos.git
   ```
3. Open `SimilarPhotos.xcodeproj` in Xcode
4. Go to **Signing & Capabilities** → select your Apple ID as the team
5. Add **Privacy - Photo Library Usage Description** in the **Info** tab if not already present
6. Connect your iPhone via USB, select it as the build target
7. Press **Cmd+R** to build and run
8. On first run, trust the developer certificate: **Settings → General → VPN & Device Management → Trust**

## How It Works

1. **Indexing** — On first launch, the app loads a thumbnail of every photo and runs it through Apple's Vision neural network (`VNGenerateImageFeaturePrintRequest`), producing a 128-number fingerprint per image. These fingerprints are saved to disk (~20 MB for 25k photos).

2. **Searching** — When you pick or paste a query image, the app computes its fingerprint and compares it against all stored fingerprints using a distance function. Only the top-N closest matches are kept in memory. The comparison is pure math — no images are loaded — so it takes seconds, not minutes.

3. **Caching** — The index persists across app launches. Only new photos are processed on subsequent runs. If Apple updates the Vision model across iOS versions, the index rebuilds automatically.

## Requirements

- iPhone running iOS 17.0 or later
- Photo library access

## Privacy

Everything runs 100% on-device. No photos, fingerprints, or data leave your phone. There is no network access, no analytics, no tracking.
