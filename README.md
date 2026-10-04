# Vibe Stage

YouTube Music, Pocket Casts, and Audible — in one Omarchy bar chip with a keyboard-first panel.

![Vibe Stage bar chip](docs/preview-bar.png)

One chip replaces three. The panel divides into source tabs: YouTube Music for your songs and playlists, Pocket Casts for your podcasts, and Audible for your audiobooks. Everything works from the keyboard.


## Built on Solfa

Vibe Stage is a fork of [Solfa](https://github.com/SirAllap/omarchy-solfa), the YouTube Music plugin by [SirAllap](https://github.com/SirAllap). Solfa's engine — the hidden Chromium browser that drives YouTube Music, the DevTools protocol bridge, the sign-in flow, the equalizer, the keyboard panel, and the Hyprland integration — is the foundation this plugin stands on. Every song you play through Vibe Stage owes its smooth experience to SirAllap's work. Thank you.

## Sources

| Source | Engine | Auth | Audio |
|---|---|---|---|
| YouTube Music | Hidden Chromium via CDP (from Solfa) | Google sign-in window | Browser audio |
| Pocket Casts | Python bridge + Pocket Casts API | Email/password | mpv |
| Audible | Python bridge + Audible API (`audible` package) | Amazon email/password | mpv with DRM decryption |

## Install

```bash
omarchy plugin add https://github.com/ninepointlabs/vibe-stage --enable
```

Requires: Omarchy, a Chromium-family browser, Python 3, mpv, and the `audible` Python package for audiobook playback.

```bash
# Audible dependency (one-time):
python3 -m venv ~/.local/share/ninepointlabs.vibe-stage/audible-venv
~/.local/share/ninepointlabs.vibe-stage/audible-venv/bin/pip install audible
```

If you already have Solfa or the Pocket Casts plugin enabled, disable them — Vibe Stage replaces both.

```bash
omarchy plugin disable io.github.sirallap.solfa
omarchy plugin disable ninepointlabs.pocketcasts
omarchy restart shell
```

## Keys

**Global** (only where the key is free; turn off in Settings):  
Super+M panel · Super+Alt+M play/pause · Super+Alt+N next · Super+Alt+B previous · Super+Alt+L like

**Bar:** left click opens the panel, middle click play/pause, right click skip, scroll sets volume, Shift+scroll seeks.

**Panel — every source:**
| Key | Action |
|---|---|
| 1 2 3 | YouTube Music / Podcasts / Audiobooks |
| ← → | Switch sub-tabs |
| Space | Play / pause |
| n / p | Next / previous |
| , / . | Skip back / forward |
| - / = | Volume down / up |
| / | Search (YTM) or filter (Audible) |
| Ctrl+, | Settings |
| Esc | Back or close |
| ? | Show all keys |

**Panel — YouTube Music:** queue, search, library, lyrics, history — same keys as Solfa. `e` play next, `a` add to queue, `R` radio, `g`/`o` artist/album, `f`/`d` like/dislike, `m` mute, `r` repeat, `s` shuffle.

**Panel — Pocket Casts:** Up Next, In Progress, New, and Podcasts tabs. `q` queue/unqueue, `m` mark played, `x` cycle speed, `r` refresh.

**Panel — Audible:** In Progress, All, and Finished sub-tabs. `s` cycles sort (Recent / Title / Author), `/` filters by title or author. Enter plays the selected book. Position syncs back to Audible every 30 seconds.

## How it works

Three bridges run as child processes of the shell, each on its own Unix socket with the same JSON-line protocol. The service routes every command — play, pause, next, volume — to whichever source is active. Only one plays at a time; starting one pauses the others.

- `bin/vibe-stage-bridge` — YouTube Music engine (forked from Solfa's `bin/solfa-bridge`, 2,888 lines). Hidden Chromium with DevTools Protocol pipe, page agent injection, equalizer. Systemd unit so the engine survives shell restarts.

- `bin/pocketcasts-bridge` — Pocket Casts engine (adapted from Tim's standalone plugin). Talks to `api.pocketcasts.com`, plays through mpv with position sync.

- `bin/audible-bridge` — Audible engine (1,177 lines). Uses the [`audible`](https://pypi.org/project/audible/) Python package for Amazon authentication and device registration. Fetches the library, requests a DRM license with decryption voucher, and plays the AAXC stream through mpv. Listening position is written back every 30 seconds so your phone picks up where you left off. Works with a venv-installed `audible` package — no system-wide dependency.

## Settings

The gear in the top-right corner opens Settings, or use `Ctrl+,`. YouTube Music settings (equalizer, browser, memory limits) are prefixed `ytmusic.` in `shell.json`. Pocket Casts and Audible settings sit under their own prefixes. Every setting also shows up in Omarchy's plugin settings screen.

## CLI

```bash
# See what's playing
omarchy-shell ninepointlabs.vibe-stage status
# Switch source
omarchy-shell ninepointlabs.vibe-stage setSource podcasts
# Play/pause on the active source
omarchy-shell ninepointlabs.vibe-stage playPause
```

Each bridge has its own CLI too:

```bash
~/.config/omarchy/plugins/ninepointlabs.vibe-stage/bin/vibe-stage-bridge status
~/.config/omarchy/plugins/ninepointlabs.vibe-stage/bin/pocketcasts-bridge status
~/.config/omarchy/plugins/ninepointlabs.vibe-stage/bin/audible-bridge status
```

## Security

Every bridge runs in a closed environment: an absolute Python from a root-owned system directory (`-I -B`), a cleared `PATH`, no session environment. mpv is started detached with `--no-config` from a trusted binary and receives decryption keys over its JSON IPC socket — never on a command line. The Audible bridge keeps credentials in a 0600 file under `$XDG_STATE_HOME`; the password is never stored.

## License

MIT. Vibe Stage is a derivative work of Solfa (MIT, Copyright (c) 2026 SirAllap) — see [LICENSE](LICENSE).