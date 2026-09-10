# omarchy-voice

> A 100% native conversational voice pair-programmer and AuDHD executive function partner for [Omarchy Linux](https://omarchy.org/). Powered by Google Gemini Multimodal Live and native PipeWire audio.

---

## Key Features

- **100% Native Wayland & Quickshell (QML):** Zero webapp, zero Chromium, zero localhost HTTP servers. Renders directly as native Wayland layer-shell surfaces matching Omarchy's Catppuccin theme.
- **Low-Latency PipeWire Audio:** Direct PCM streaming through PipeWire (`pw-cat -r` for 16kHz microphone capture, `pw-cat -p` for 24kHz speaker playback) with instant barge-in / speech interruption.
- **AuDHD Executive Function Partner:**
  - **Autonomous Capture:** Infers and logs actionable GitHub issues directly from natural dialogue without requiring tedious administrative instructions.
  - **Tangent Parking Lot:** Safely catches lateral ideas and stashes them so you don't burn working memory, then provides breadcrumbs back to your main thread.
  - **Multi-Repo Domain Routing:** Classifies ideas to the right repository automatically.
  - **Paralysis Breaker:** Uses 'Eat the Frog' and 'Bang for Buck' heuristics to narrow multiple competing tasks down to one single bite-sized step.
- **Desktop Situational Awareness:** Inspects your active Hyprland window, application, and terminal working directory so it knows what you are looking at on screen.
- **Zero Secrets / Zero Hardcoding:** Automatically detects your identity and repositories via `gh api user` and `gh repo list`. Secrets are stored strictly outside the git tree.

---

## Prerequisites

- [Omarchy](https://omarchy.org/) (Arch Linux + Hyprland + Quickshell)
- PipeWire (`pw-cat` utility)
- [`uv`](https://docs.astral.sh/uv/) (Python package runner)
- GitHub CLI (`gh`) authenticated (`gh auth login`)
- Google Gemini API Key

---

## Installation

```bash
# 1. Add as an Omarchy plugin
omarchy plugin add https://github.com/John-Dennehy/omarchy-voice --enable

# 2. Configure your Gemini API key (outside git repo)
mkdir -p ~/.config/omarchy/voice
echo "GEMINI_API_KEY=your_key_here" > ~/.config/omarchy/voice/env
chmod 600 ~/.config/omarchy/voice/env
```

---

## Configuration

Customize your personal working style, preferred voice, and principles in `~/.config/omarchy/voice/config.json`:

```json
{
  "voice": {
    "name": "Charon",
    "accent": "british"
  },
  "user": {
    "name": "Your Name",
    "style": "AuDHD pair programming, thinking out loud, low executive load"
  },
  "principles": [
    "1 fork: limit active work-in-progress to one branch",
    "eat the frog: tackle highest-friction blockers first",
    "bang for buck: evaluate tasks by highest leverage"
  ],
  "projects": {
    "autoDiscover": true,
    "scanDirs": ["~/Projects"]
  }
}
```

---

## Controls & Keybindings

Add to your `~/.config/hypr/bindings.lua`:

```lua
-- Super + R: Toggle compact floating voice pill
o.bind("SUPER + R", "Toggle Voice Assistant (Mini)", "omarchy-voice toggle")

-- Super + Shift + R: Toggle full voice drawer (transcript, parking lot, repos)
o.bind("SUPER + SHIFT + R", "Toggle Voice Assistant (Full)", "omarchy-voice expand")
```

| Action | Shortcut / Trigger |
| :--- | :--- |
| **Toggle Mini Pill** | <kbd>Super</kbd> + <kbd>R</kbd> |
| **Toggle Full Drawer** | <kbd>Super</kbd> + <kbd>Shift</kbd> + <kbd>R</kbd> (or `󰁌` on pill) |
| **Minimize Drawer to Pill** | <kbd>Esc</kbd> (or `󰁍` button) |
| **Toggle Mute** | `󰍬` / `󰍭` button (or `omarchy-voice mute`) |

---

## Architecture

```
                 ┌───────────────────────────────────────┐
                 │       Native Quickshell UI (QML)      │
                 │  - Mini Overlay Pill (WlrLayer.Overlay)│
                 │  - Expanded Drawer Modal (with Scrim)  │
                 └──────────────────┬────────────────────┘
                                    │ (stdio IPC)
                 ┌──────────────────┴────────────────────┐
                 │     Headless Python Engine (uv)       │
                 │  - Dynamic gh identity & repo routing │
                 │  - Hyprland desktop context snooper   │
                 └──────────┬─────────────────┬──────────┘
                            │                 │
            PipeWire Native Audio         Gemini Multimodal Live
         (pw-cat -r / pw-cat -p)       (BidiGenerateContent WS)
```

---

## License

[MIT License](LICENSE) © 2026 John Dennehy
