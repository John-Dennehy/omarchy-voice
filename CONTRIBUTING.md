# Contributing to omarchy-voice

Thank you for helping build `omarchy-voice`! We aim to create a fast, distraction-free, 100% native voice pair-programmer and AuDHD executive function partner for Omarchy Linux.

---

## Core Tenets

1. **100% Native:** Zero webviews, zero Chromium runtimes, zero localhost HTTP daemons. UI components must remain native Wayland layer-shell surfaces (via Quickshell / QML) and audio must stream directly through PipeWire (`pw-cat`).
2. **Zero Hardcoded Secrets & Context:** Never commit API keys, personal emails, or hardcoded personal paths. Identity and repos must be discovered dynamically via CLI (`gh api user`, `gh repo list`). User credentials belong strictly in `~/.config/omarchy/voice/env`.
3. **Executive Function First:** Interactions should minimize cognitive load—smart defaults, autonomous triage, parking lot for lateral thoughts, and zero nagging.
4. **Decoupled Keybindings:** Do not prescribe global shortcuts; provide CLI and bar widget affordances, leaving keybinding customization to the user's `bindings.lua`.

---

## Development & PR Workflow

1. **Branching:**
   - Create a feature branch off `main`: `git checkout -b feat/your-feature-name` or `fix/your-bugfix`.
2. **Validation:**
   Ensure all checks pass locally before opening a pull request:
   ```bash
   python3 -m py_compile daemon.py
   omarchy plugin validate .
   bash -n bin/omarchy-voice
   ```
3. **Pull Requests:**
   - Open a PR against `main`.
   - Link any tracked GitHub issues using `closes #XX` in your PR description.
   - GitHub Actions CI will validate syntax, manifest schema, and scripts.
4. **Branch Protection:**
   - All PRs require passing CI status checks before merging.
   - Merges use linear history (squash or rebase).

---

## Guidelines for New Voice Providers

If adding support for a new voice provider (e.g., local Whisper/Piper, OpenAI Realtime, etc.):
- Inherit from `BaseVoiceProvider` in `daemon.py`.
- Implement `is_available()`, `run()`, and map incoming tools to `TOOLS_MAP`.
- Add provider identifier to `PROVIDERS` dictionary and update `manifest.json` schema options.
