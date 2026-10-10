# MetroLegacy

**MetroLegacy** is a native YouTube Music client designed for iOS 6+.

Inspired by the interface, design, and user experience of **[Metrolist](https://github.com/MetrolistGroup/Metrolist)** for Android, but reimplemented from scratch in pure **Objective-C** on top of classic UIKit and Theos.

---

## Features

- **Smooth Native Playback:** Direct AAC/MP4 audio streaming via `AVPlayer` using a local loopback HTTP relay (`127.0.0.1`) with support for HTTP range requests (`206 Partial Content`).
- **Modern TLS Certificate Bypass:** Custom TLS trust evaluation with bundled Google Trust Services (GTS R1–R4) root anchors, allowing connections to modern YouTube and Google Video APIs on legacy operating systems where system root certificates have expired.
- **Material 3-Inspired Interface:** Rounded cards, dark theme with modern accents, tailored for both classic 3.5-inch (iPhone 4/4s) and 4-inch (iPhone 5/5c) displays.
- **Search & Browse:** YouTube Music search with filters for songs, albums, artists, and playlists.
- **Cover Art Caching:** Secure thumbnail and artist avatar downloading with efficient downscaling and disk storage optimized for 512 MB RAM devices.
- **Mini-Player & Queue:** Persistent mini-player bar and full-screen playback interface with playback controls and queue view.

---

## Build Requirements

- **Toolchain:** [Theos](https://theos.dev)
- **Target SDK:** iOS 7.1 SDK
- **Deployment Target:** iOS 6.0+
- **Architecture:** `armv7`

### Build and Install:

```bash
# Build .deb package
make package FINALPACKAGE=1

# Generate .ipa package
make package FINALPACKAGE=1 PACKAGE_FORMAT=ipa
```

---

## License & Credits

This project is licensed under the **GNU General Public License v3.0** (GPLv3). See the [`LICENSE`](LICENSE) file for more details.

### Acknowledgments:
- **[Metrolist (Android)](https://github.com/MetrolistGroup/Metrolist)**: Visual design concept, flow, and user experience inspiration.
