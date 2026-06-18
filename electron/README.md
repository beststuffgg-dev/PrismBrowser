# Prism (Electron) — Windows / macOS / Linux

A cross-platform Electron port of Prism, the 3D-aesthetic browser with a
built-in multi-provider AI agent. It mirrors the native macOS (SwiftUI) app:
WebKit-style tabbed browsing (via `<webview>`), a live spinning 3D backdrop
(Three.js), `.3mf` model loading, customizable **3D geometric start-page
wallpapers**, and an agentic AI sidebar that works with **Claude, ChatGPT,
Gemini, Perplexity and DeepSeek**.

## Run from source

```bash
cd electron
npm install
npm start
```

## Build installers

Installers are produced by [electron-builder](https://www.electron.build/):

```bash
npm run dist        # Windows .exe (NSIS) — run on Windows
npx electron-builder --mac     # macOS .dmg   — run on macOS
npx electron-builder --linux   # Linux bundle — run on Linux
```

Output lands in `electron/dist/`. CI builds these automatically — see
`.github/workflows/build-electron.yml` (Windows + macOS) and the Linux
workflows on the `Prismatix-ubuntu` (.deb) and `Prismatix-arch` (.pacman)
branches.

## Architecture

| File | Role |
|------|------|
| `src/main.js` | Electron main process; window + `net:fetch` proxy (dodges provider CORS) |
| `src/preload.js` | Context-isolated bridge exposing `window.prism.netFetch` |
| `src/renderer/index.html` / `styles.css` | UI shell + retro-3D theme |
| `src/renderer/app.js` | Tabs, `<webview>` browsing, toolbar, settings, AI wiring |
| `src/renderer/scene.js` | Live 3D backdrop (Three.js) |
| `src/renderer/wallpaper.js` | 3D geometric start-page wallpapers (presets + colors) |
| `src/renderer/model3mf.js` | `.3mf` → Three.js geometry |
| `src/renderer/ai.js` | Multi-provider agent (Anthropic / OpenAI-style / Gemini) |

## AI keys

Open Settings (⚙), pick a provider, paste its key. Keys are held in memory
only (never written to disk); provider/model/wallpaper choices are saved to
`localStorage`. All provider traffic is proxied through the main process so the
renderer never hits CORS.
