# omarchy-voice

> A 100% native conversational voice pair-programmer and AuDHD executive function partner for [Omarchy Linux](https://omarchy.org/).

---

## Overview & Philosophy

`omarchy-voice` is built from the ground up for Omarchy Linux to act as a real-time, lateral-thinking thinking partner and executive function wingman. It eliminates browser windows, electron runtimes, localhost webservers, and heavy web stacks in favor of 100% native Wayland layer-shell surfaces and direct PipeWire audio streaming.

### Long-Term Vision: Pluggable AI Backends

While the current MVP leverages Google's Gemini Multimodal Live API for low-latency bidirectional voice turns, **the core project is designed to be provider-agnostic**. The assistant should work with whatever AI tools, models, or local runtimes the user has access to or prefers:

- **Cloud Voice APIs:** Gemini Multimodal Live, OpenAI Realtime API.
- **Agentic LLMs + Audio Pipelines:** Anthropic Claude, OpenAI, or Fireworks paired with streaming STT/TTS.
- **Local & Offline:** Whisper / faster-whisper paired with local LLMs (via Ollama / llama.cpp) and lightweight TTS (Piper / Kokoro) for complete privacy and offline operation.
- **Omarchy Agent Ecosystem:** Seamless delegation to the system's active `omarchy-default-agent` (`agy`, `claude`, `codex`, `copilot`, `crush`, etc.).

Tracking Issue: [#6: Abstract voice runtime to support pluggable multi-provider backends](https://github.com/John-Dennehy/omarchy-voice/issues/6)

---

## Key Features

- **100% Native Wayland & Quickshell (QML):** Zero webapp, zero Chromium, zero localhost HTTP servers. Renders directly as native Wayland layer-shell surfaces matching Omarchy's system theme tokens.
- **Low-Latency PipeWire Audio:** Direct PCM streaming through PipeWire (`pw-cat -r` for 16kHz microphone capture, `pw-cat -p` for 24kHz speaker playback) with instant barge-in / speech interruption.
- **AuDHD Executive Function Support:**
  - **Autonomous Capture:** Infers and logs actionable GitHub issues directly from natural dialogue without requiring tedious administrative instructions.
  - **Tangent Parking Lot:** Safely catches lateral thoughts and stashes them so you don't burn working memory, then provides breadcrumbs back to your main thread.
  - **Multi-Repo Domain Routing:** Classifies ideas to the right repository automatically.
  - **Paralysis Breaker:** Uses 'Eat the Frog' and 'Bang for Buck' heuristics to narrow multiple competing tasks down to one single bite-sized step.
- **Desktop Situational Awareness:** Inspects your active Hyprland window, application, and terminal working directory so it knows what you are looking at on screen.
- **Zero Secrets / Zero Hardcoding:** Automatically detects your identity and repositories via `gh api user` and `gh repo list`. Secrets and configurations live strictly outside the git tree.

---

## Interaction & Invocation

`omarchy-voice` never prescribes or dictates global keybindings. Desktop controls belong to the user. The assistant is designed to be invoked through native desktop affordances:

1. **Omarchy Status Bar Widget:**
   - Lives directly on your Omarchy bar.
   - **Visual indicator:** Glows accent when listening, green when speaking, amber when running actions, and red when muted.
   - **Left-click:** Toggle floating voice pill overlay.
   - **Right-click:** Toggle mute / unmute.
   - **Middle-click:** Expand full drawer modal (transcript, parking lot, repo switcher).
2. **AI Workspace Integration (Co-Pilot):**
   - Integrates alongside your configured AI coding workspace (e.g. `special:agent` with `omarchy-agent`), serving as a voice companion alongside your terminal agent rather than replacing it.
3. **CLI & IPC (`omarchy-voice`):**
   - `omarchy-voice toggle`: Toggle compact overlay pill.
   - `omarchy-voice expand`: Open full drawer modal.
   - `omarchy-voice mute`: Toggle microphone mute.
   - `omarchy-voice dismiss`: Close overlay.
4. **Optional Custom Keybindings (User Choice):**
   Users who wish to bind keyboard shortcuts can add their preferred chords to `~/.config/hypr/bindings.lua` (for example):
   ```lua
   -- Example optional bindings (pick whatever keys you prefer):
   o.bind("SUPER + R", "Toggle Voice Assistant", "omarchy-voice toggle")
   o.bind("SUPER + SHIFT + R", "Voice Assistant Drawer", "omarchy-voice expand")
   ```

---

## Installation & Setup

```bash
# 1. Add as an Omarchy plugin
omarchy plugin add https://github.com/John-Dennehy/omarchy-voice --enable

# 2. Place widget on your bar (e.g. next to agents)
omarchy bar put jd.voice --after omarchy.agents

# 3. Configure credentials in user environment (outside git repo)
mkdir -p ~/.config/omarchy/voice
echo "GEMINI_API_KEY=your_key_here" > ~/.config/omarchy/voice/env
chmod 600 ~/.config/omarchy/voice/env
```

---

## User Configuration

Personal working style, principles, and preferences are stored in `~/.config/omarchy/voice/config.json`:

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

## Architecture

```
                 ┌───────────────────────────────────────┐
                 │       Native Quickshell UI (QML)      │
                 │  - Mini Overlay Pill (WlrLayer.Overlay)│
                 │  - Expanded Drawer Modal (with Scrim) │
                 │  - Native Omarchy Bar Widget (qs.Ui)  │
                 └──────────────────┬────────────────────┘
                                    │ (stdio IPC)
                 ┌──────────────────┴────────────────────┐
                 │     Headless Python Engine (uv)       │
                 │  - Dynamic gh identity & repo routing │
                 │  - Hyprland desktop context snooper   │
                 │  - Pluggable voice backend interface  │
                 └──────────┬─────────────────┬──────────┘
                            │                 │
            PipeWire Native Audio         Conversational LLM
         (pw-cat -r / pw-cat -p)       (Gemini Live / OpenAI / Local)
```

---

## License

[MIT License](LICENSE) © 2026 John Dennehy

