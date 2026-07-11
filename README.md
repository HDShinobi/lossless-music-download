<div align="center">

<img src="branding/app_icon.png" alt="Lossless Music" width="120" />

# Lossless Music

### Own genuine, *verifiable* lossless audio — for ears that don't settle.

**Sở hữu nhạc lossless đích thực, chất lượng có thể kiểm chứng.**

<p>
  <img alt="Version"  src="https://img.shields.io/badge/version-0.5.7-1DB954?style=flat-square" />
  <img alt="Platform" src="https://img.shields.io/badge/platform-Android%206.0%2B-3DDC84?style=flat-square&logo=android&logoColor=white" />
  <img alt="Flutter"  src="https://img.shields.io/badge/UI-Flutter-02569B?style=flat-square&logo=flutter&logoColor=white" />
  <img alt="Go"       src="https://img.shields.io/badge/engine-Go-00ADD8?style=flat-square&logo=go&logoColor=white" />
  <img alt="License"  src="https://img.shields.io/badge/license-MIT-lightgrey?style=flat-square" />
</p>

<p>
  <a href="https://github.com/HDShinobi/lossless-music-releases/releases/latest"><b>⬇️  Download APK</b></a>
  &nbsp;·&nbsp;
  <a href="https://losslessmusic.xyz">🌐 Website</a>
  &nbsp;·&nbsp;
  <a href="#-build-from-source">🛠️ Build</a>
</p>

</div>

---

**Lossless Music** downloads high-resolution audio, **proves it's truly lossless** with a
spectral-frequency analysis of every file, and streams your verified library to any player
on your local network. It is **not a music player** — it's the piece that *builds and serves*
a trustworthy hi-fi library to the players you already love (PureBit, UAPP, Poweramp…).

The app ships as an **empty frame**. You bring your own source aggregator; extensions then run
inside a **sandbox** you control, allowed to touch only the domains and files they declare
up-front. Nothing activates on its own — and no music sources are bundled.

---

## ✨ Why it's different

| | Feature | What it does |
|---|---|---|
| 🔬 | **Verifiable lossless** | Auto-generates a spectrogram for every download. A real FLAC keeps the full frequency range; an MP3-320 faked as FLAC gets cut off around ~16 kHz. You *see* the difference instead of trusting a filename. |
| 🧩 | **Bring-your-own sources** | Downloads run through sandboxed JS extensions **you** install. The app declares no built-in sources and grants each extension only the domains it needs. |
| 🔁 | **Multi-source + auto-fallback** | When one source fails or rate-limits (HTTP 429), it honors the server's `Retry-After` and falls back to the next source — batch and full-album downloads recover cleanly. |
| 🏷️ | **Rich metadata, done right** | Embeds tags, cover art, synced lyrics (`.lrc` sidecar) and ReplayGain so your player behaves consistently across the whole library. |
| 📡 | **Serve your library** | Broadcasts the verified library over **DLNA/UPnP** and **WebDAV** to any renderer on your LAN. |
| 🔐 | **Safe self-updates** | Distributed as a direct APK. Every release publishes a **SHA-256** hash, and the app verifies each new build before installing. |

---

## ⬇️ Install

> Android 6.0+ · installs outside the Play Store.

1. Grab the latest APK from the **[Releases page](https://github.com/HDShinobi/lossless-music-releases/releases/latest)**.
2. Verify the file against the published **SHA-256** hash.
3. Enable *Install unknown apps* for your browser/file manager, then open the APK.

```
https://github.com/HDShinobi/lossless-music-releases/releases/download/v0.5.7/lossless-music-v0.5.7.apk
```

---

## 🧱 How it works

```
┌──────────────────────────────────────────────────────────┐
│  Flutter UI (lib/)          search · queue · library · UI  │
├──────────────────────────────────────────────────────────┤
│  Native bridge (gomobile)   Dart  ⇄  Go                    │
├──────────────────────────────────────────────────────────┤
│  Go engine (go_backend/)    downloads · FFmpeg metadata ·  │
│                             sandboxed JS extensions (goja) │
│                             DLNA/UPnP · WebDAV · spectral   │
└──────────────────────────────────────────────────────────┘
```

- **UI** — a fresh Flutter rebuild (our own screens & widgets).
- **Engine** — a Go download/file-management core based on the [SpotiFLAC](https://github.com/spotiflacapp/SpotiFLAC-Mobile) architecture (MIT), kept close to upstream and bridged to Flutter via gomobile.
- **Extensions** — JavaScript, executed in a locked-down [goja](https://github.com/dop251/goja) sandbox with an explicit domain/file allow-list.

---

## 🛠️ Build from source

**Prerequisites:** Flutter (stable), Go 1.22+, Android NDK, and `gomobile`.

```bash
# 1. Build the Go engine into an Android archive (.aar) via gomobile
cd go_backend
gomobile bind -target=android -o ../android/app/libs/backend.aar .

# 2. Build the Flutter app
cd ..
flutter pub get
flutter build apk --release
```

The signed APK lands in `build/app/outputs/flutter-apk/`.

---

## 🧭 Philosophy

> **This is a source, not a sink.**
> Lossless Music doesn't play music and doesn't host it. It builds a *verified* high-quality
> library and hands it to the player of your choice. You stay in control of where the music
> comes from.

---

## ⚖️ Disclaimer

This is a **personal, non-commercial project for research and educational purposes**. It is not
affiliated with any music service, **hosts no music, and ships with no sources**. Any content is
provided by extensions the user chooses to install. The `go_backend/` engine is vendored from
SpotiFLAC (MIT) and kept pristine to ease upstream syncs.

## 📄 License

Released under the [MIT License](LICENSE).

---

<div align="center">
<sub>Made for people who can hear the difference · <a href="https://losslessmusic.xyz">losslessmusic.xyz</a></sub>
</div>
