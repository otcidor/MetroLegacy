# MetroLegacy

<p align="center">
  <img src="Resources/Icon@2x.png" alt="MetroLegacy Icon" width="120" height="120" style="border-radius: 24px;">
</p>

<p align="center">
  <strong>Native YouTube Music client for iOS 6.0 - 10+</strong><br>
  Universal binary for <code>armv7</code> (32-bit legacy) and <code>arm64</code> (64-bit modern).<br>
  Built from scratch in pure <strong>Objective-C</strong> using <strong>Theos</strong>.
</p>

<p align="center">
  <a href="https://github.com/MetrolistGroup/Metrolist"><img src="https://img.shields.io/badge/Inspired%20by-Metrolist%20Android-ED5564.svg" alt="Metrolist"></a>
  <img src="https://img.shields.io/badge/Target-iOS%206.0%2B-blue.svg" alt="iOS 6.0+">
  <img src="https://img.shields.io/badge/Arch-armv7%20%7C%20arm64-green.svg" alt="Architectures">
  <img src="https://img.shields.io/badge/Version-1.2.3-orange.svg" alt="Version 1.2.3">
  <img src="https://img.shields.io/badge/License-GPLv3-lightgrey.svg" alt="GPLv3">
</p>

---

## Overview

**MetroLegacy** brings the modern YouTube Music experience to legacy and vintage iOS devices. Inspired by the clean, fluid Material 3 design and workflow of **[Metrolist](https://github.com/MetrolistGroup/Metrolist)** (Android), MetroLegacy is an independent reimplementation engineered specifically for resource-constrained legacy Apple hardware.

It communicates directly with YouTube Music's internal InnerTube REST API (`music.youtube.com/youtubei/v1/*`) without requiring official Google Play Services, modern frameworks, or bloated web runtimes.

---

## Key Features

### High-Performance Audio Engine and Streaming Pipeline
- **Loopback Stream Relay (`MLStreamRelay`):** Resolves legacy TLS handshake issues and codec limitations by running a high-throughput local loopback HTTP relay on `127.0.0.1`:
  - **iOS 6 (`armv7`):** Streams progressive ADTS AAC (`stream.aac`) parsed on-the-fly from YouTube DASH SIDX fragments into elementary ADTS frames. Completely bypasses the CoreMedia container limitation (OSStatus error `-12842` / `kAudioFileUnsupportedFileTypeError`) while allowing real-time DSP tapping.
  - **iOS 7+ (`armv7` and `arm64`):** Streams progressive MP4 (`stream.mp4`) with full HTTP 206 Partial Content range requests.
  - **Local and Cached Audio Playback:** Solves offline playback on iOS 6 for DASH-fragmented MP4 (`ftypdash`) files downloaded into the cache. Local files are demuxed directly via `NSFileHandle` and served through the relay as `stream.aac`, enabling full offline playback and equalizer processing.
- **Robust DASH Fragment Delivery:**
  - Automatically handles upstream HTTP 416 Range Unsatisfiable responses with open-ended range queries (`bytes=start-`) to retrieve final audio fragments cleanly.
  - Calculates exact physical audio durations from SIDX boxes (`durationForStreamURL:`), preventing duration mismatches between video metadata and physical audio streams.
  - Detects stream completion and serves clean HTTP 200 EOF (`Content-Length: 0`) on subsequent reconnection requests, preventing track looping or unexpected restarts at the end of songs.
- **Precision Seeking:** Instant seeking on iOS 6 through the `?startSec=` parameter, which resolves the exact SIDX segment offset and streams immediately without AVPlayer buffering stalls.

### Material 3 User Interface
- **Pure UIKit Implementation:** Hand-crafted Material 3 components running natively on iOS 6 UIKit without modern Auto Layout overhead or WebViews: pill filter chips, rounded cards (`r28`), thumbnails (`r3`), and modal bottom sheets.
- **Dynamic Theming:** Real-time dominant color extraction from album artwork to tint playback controls, progress bars, and ambient accents (`MLTheme`).
- **Equalizer Screen (`MLEqualizerViewController`):** Dedicated UI with vertical rotated sliders, numerical dB readouts, snap-to-zero detents, preset chips scroll view, master toggle switch, and animated reset.
- **Adaptive Layouts:** Fully responsive across classic 3.5-inch, 4-inch, and iPad tablet display sizes.

### Offline Downloads and Library Management
- **Local Audio Caching and Downloads:** Download favorite songs and playlists directly to device storage for offline playback.
- **Dual-Tier Image Cache (`MLImageCache`):** Multithreaded background image downloader with disk caching, memory pooling, and strict dimension limits designed for 512 MB RAM devices.

### Smart Playback and System Integration
- **SponsorBlock Integration (`MLSponsorBlockManager`):** Automatically skips sponsored segments, intros, outros, and non-music interludes based on the public SponsorBlock database.
- **Synchronized Lyrics (`MLLyricsManager`):** Real-time timed scrolling and active line highlighting synchronized with the audio playhead.
- **Listen Together:** Synchronized real-time group listening rooms.
- **System Remote Controls:** Complete integration with `MPNowPlayingInfoCenter`, lockscreen album art, and headphone/control center remote control events.
- **Diagnostic Logging:** On-device stderr redirection to `Documents/MetroLegacy.log` for runtime inspection and troubleshooting.

---

## Supported iOS Versions

| Platform | Deployment Target | Architectures | Pipeline Support |
|---|---|---|---|
| **iOS 6.0 - 6.1.6** | 6.0 | `armv7` (32-bit legacy) | Progressive ADTS AAC relay (`stream.aac`) and CoreAudio fallback tap |
| **iOS 7.0 - 10.3.4** | 6.0 (Universal) | `armv7` and `arm64` | Progressive MP4 streaming (`stream.mp4`) and native fMP4 playback |
| **iOS 11.0+** | 6.0 (Universal) | `arm64` (64-bit modern) | Universal binary execution on modern 64-bit environments |

---

## Build Requirements and Instructions

The project is compiled using **[Theos](https://theos.dev)**.

### Prerequisites:
- macOS or Linux with Theos installed (`$THEOS` environment variable configured).
- iOS 7.1 SDK (or compatible patched toolchain supporting deployment target 6.0).

### Compiling and Packaging:

```bash
# Clean previous build artifacts
make clean

# Compile universal binary (armv7 + arm64) and create .deb and .ipa packages
make package FINALPACKAGE=1
```

The build system automatically generates packages in the `packages/` directory:
- `packages/MetroLegacy.ipa`
- `packages/win.otcidor.metrolegacy_1.2.3_iphoneos-arm.deb`

---

## Architecture and Code Structure

```
├── Makefile                    # Theos build configuration (universal armv7 + arm64)
├── control                     # Debian package control file (v1.2.3)
├── Resources/                  # Localizations, Info.plist, icons, po_client.html
├── src/
│   ├── App/                    # App delegate, window hierarchy, navigation styling
│   ├── Account/                # Google Device Flow authorization
│   ├── Core/                   # Theme (M3), ImageCache, Lyrics, SponsorBlock, TLS Trust
│   ├── InnerTube/              # YouTube Music API parsing, cipher, and stream resolution
│   ├── Player/
│   │   ├── MLPlaybackManager   # AVPlayer queue, periodic observation, track advancement
│   │   ├── MLStreamRelay       # Loopback HTTP server, SIDX DASH parsing, ADTS AAC streaming
│   │   └── MLEqualizerManager  # CoreAudio MTAudioProcessingTap + vDSP 10-band EQ
│   └── UI/                     # Home, Search, Player, Equalizer, Queue, Library, Tabs
```

---

## License and Credits

MetroLegacy is open-source software licensed under the **GNU General Public License v3.0** (GPLv3). See [`LICENSE`](LICENSE) for details.

### Acknowledgments:
- **[Metrolist (Android)](https://github.com/MetrolistGroup/Metrolist)**: User interface, flows, and design inspiration.
- **Theos Team**: Build system for iOS jailbreak and legacy toolchains.
