# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

VlogForge (repo/app also called AutoVlogs): a macOS 13+ AppKit app that turns a folder of videos/photos into a short chronological vlog MP4. SwiftPM package, one executable target, no external Swift dependencies. UI strings, prompts, error messages and README are in Spanish — keep new user-facing text in Spanish.

Runtime tools (shelled out to, not linked):
- **FFmpeg** (required) — looked up at `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`.
- **Ollama** (optional) — HTTP at `127.0.0.1:11434`; model auto-detected or forced with `VLOGFORGE_OLLAMA_MODEL`.
- **whisper.cpp** (optional) — `VLOGFORGE_WHISPER_BIN` / `VLOGFORGE_WHISPER_MODEL`, otherwise searched under `~/whisper.cpp` then Homebrew paths, preferring large-v3-turbo → large-v3 → medium → small → base.

## Commands

```bash
swift run                                   # launch the GUI
swift build -c release                      # binary at .build/release/VlogForge
.build/release/VlogForge --self-test /path/to/folder   # headless render → <folder>/vlogforge-self-test.mp4
.build/release/VlogForge --snapshot out.png [folder]    # render the window to a PNG (no Screen Recording permission needed) and quit
```

There are no unit tests or linter. `--self-test` is the only automated check; add `--ai` as a 4th argument to also run Whisper + Ollama.

`outputs/` holds committed, prebuilt artifacts (`outputs/VlogForge` binary, `VlogForge.app`, `AutoVlogs.app`, `Launch-AutoVlogs.command` which runs `outputs/VlogForge` and logs to `outputs/AutoVlogs.log`). There's no build script for them — after a release build, the binary is copied in by hand.

## Architecture

Everything is in `Sources/VlogForge/main.swift`. Top-level code at the bottom picks `--self-test` or starts `NSApplication`. `AppDelegate` holds both the UI and the whole pipeline as `static` functions:

1. `scan` — runs as the first step of "Generar vlog" (choosing a folder only counts files via `mediaFiles`); recursive folder walk; items sorted by capture date (AVAsset `creationDate` / photo EXIF, falling back to modification date); fully black videos are dropped.
2. `transcribe` (optional) — extract audio with FFmpeg, run whisper-cli, parse into `SpeechSegment`s on each `MediaItem`.
3. `selectMoments` — `buildCandidates` makes windows per video (each Whisper phrase whole, merged ≤12 s, plus 5 s windows over silent parts) scored locally from speech, laugh marks in the transcript (Whisper is prompted with "(risas)"), loudness peaks and brightness (`analyzeSignals`, one FFmpeg pass). `OllamaClient.rate` sends batches of 12 with one contact sheet (3 frames per candidate) to the vision model → interest 1–10 + a description that names visible emotions. `OllamaClient.story` (text-only, largest installed model) states the main plot and gives each moment a `tipo` (risa, emocion, tonteria, hito, recapitulacion, contexto, tecnico, relleno) and plot relevance; tecnico/relleno are dropped, the others get `kindBonus`. Greedy pick up to the target duration (max 3 per source), then `OllamaClient.fileCaptions` writes ONE text per source video summarising the whole file within the plot — every clip from that file shows it.
4. `render` — per segment: draw a transparent PNG overlay (date stamp + title) with AppKit, then FFmpeg scales/pads to the canvas (largest real source resolution, never upscaled), overlays it, adds silent audio if missing, encodes H.264/AAC 30fps. Clips are joined with the concat demuxer (`-c copy`), so every clip must share identical encode params.

Gotchas:
- Overlay drawing must happen on the main thread (`DispatchQueue.main.sync` inside `render`); off-main AppKit drawing silently produces a blank PNG.
- Ollama failure must never block export — the code falls back to local scores.
- qwen3-vl costs ~1000 tokens per image regardless of size, hence one contact sheet per batch. Thinking models return the JSON in `thinking` with `response` empty; both are read.
- Pixel metrics (blurdetect, YDIF) were tested on real camcorder footage and did not separate bad shots; shot quality is judged by the vision model instead.
- Captions: small models quote the dialogue or copy prompt examples; `captions` filters both. Without Ollama no captions are drawn (a dull transcript fragment is worse than none).
