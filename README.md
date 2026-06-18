# Prism — a 3D-aesthetic macOS browser with a built-in AI agent

Prism is a native macOS browser built with SwiftUI + WebKit. It pairs a real
WebKit browsing engine with a retro 3D-modeling look (beveled metal chrome,
tilted glass panels, neon wireframe accents) and a built-in agent that can
drive the browser through Claude, ChatGPT, Gemini, Perplexity or DeepSeek.

## Platforms & variants

| Platform | Implementation | Where | Installer |
|----------|----------------|-------|-----------|
| macOS | Native SwiftUI + WebKit + SceneKit | this branch (`Sources/`) | `.dmg` |
| Windows / macOS | Electron (Three.js) | this branch (`electron/`) | `.exe` / `.dmg` |
| Ubuntu / Debian | Electron | branch `Prismatix-ubuntu` | `.deb` + AppImage |
| Arch Linux | Electron | branch `Prismatix-arch` | `.pacman` + AUR `PKGBUILD` |

The Electron port mirrors the native app feature-for-feature and adds
**customizable 3D geometric start-page wallpapers**. See `electron/README.md`.

## Features

- **Real browsing** — WebKit (`WKWebView`) per tab, address/search bar, back /
  forward / reload, multi-tab strip, live progress.
- **Whole-UI 3D treatment** — every surface is styled with bevels, gloss,
  drop shadows and subtle perspective tilt (`rotation3DEffect`). The toolbar
  reads as an extruded metal slab; the AI panel is a tilted glass slate.
- **Live spinning 3D scene** — a SceneKit view renders continuously behind the
  UI: a procedural neon wireframe object by default, orbitable with the mouse.
- **Customizable with .3mf models** — click the cube button (or Settings →
  Load .3mf) to swap in your own [3MF](https://3mf.io) model. Prism parses the
  mesh and renders it as a glowing wireframe + flat-shaded body.
- **Agentic AI, any provider** — the side panel chats with your choice of
  **Claude, ChatGPT, Gemini, Perplexity or DeepSeek**. With **Agent** mode on,
  the model can call browser tools (`navigate`, `open_tab`, `read_page`,
  `go_back`) in a loop to actually accomplish web tasks, with each action shown
  in the transcript. (Perplexity runs as a plain chat — its API has no tool
  calling.)

## Requirements

- macOS 13 (Ventura) or later
- Xcode 15+ / Swift 5.9+ command-line tools

## Build & run

From the `PrismBrowser` folder:

```bash
swift run
```

The first launch compiles the package and opens the Prism window. (You can also
open `Package.swift` in Xcode and hit Run.)

### Package as a .dmg

To build a distributable app + disk image:

```bash
./build_dmg.sh
```

This compiles a release build, assembles `Prism.app`, ad-hoc signs it, and
writes a drag-to-Applications installer to `dist/Prism.dmg`. Since it isn't
notarized, the first launch needs right-click → Open.

### Build the .dmg on GitHub (no Mac needed locally)

This repo ships a GitHub Actions workflow (`.github/workflows/build-dmg.yml`)
that builds the DMG on a macOS runner. Once the repo is on GitHub:

1. Push to `main` (or open the **Actions** tab → *Build Prism DMG* → **Run
   workflow**).
2. When the run finishes, open it and download **Prism-dmg** from the
   *Artifacts* section.

To attach the DMG to a versioned download, publish a **Release** — the workflow
will build and upload `Prism.dmg` to that release automatically.

## Using the AI agent

1. Click the gear icon and pick a **provider** (Claude, ChatGPT, Gemini,
   Perplexity or DeepSeek).
2. Paste that provider's API key (or set its environment variable before
   `swift run`): `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`,
   `PERPLEXITY_API_KEY` or `DEEPSEEK_API_KEY`.
3. Optionally change the model (each provider has a sensible default).
4. Keep **Agent** toggled on, then type a goal, e.g.
   *"open Hacker News and summarize the top story."*
   The agent will navigate, read the page, and report back.

> Keys are held only in memory for the session and sent directly to the
> selected provider's API. Nothing is persisted to disk. Each provider keeps
> its own key, so you can switch between them freely.

## Loading a 3D model

Click the **cube** button in the toolbar and choose a `.3mf` file. A sample
`SampleCube.3mf` is included next to this README. Drag to orbit the camera;
use Settings → Reset to return to the default wireframe object.

## Project layout

| File | Role |
|------|------|
| `PrismApp.swift` | App entry; wires browser + AI together |
| `ContentView.swift` | Full UI: toolbar, tabs, content frame, AI sidebar, settings |
| `Theme.swift` | The 3D look — gradients, bevels, chrome button style |
| `BrowserState.swift` | Tab model, navigation, WebKit KVO bridging |
| `WebView.swift` | `WKWebView` ↔ SwiftUI bridge |
| `Scene3DView.swift` | Live SceneKit scene + model store |
| `Model3MF.swift` | `.3mf` parser → `SCNGeometry` |
| `AIProvider.swift` | Provider catalog (Claude/ChatGPT/Gemini/Perplexity/DeepSeek) + normalized tool/message types |
| `AIController.swift` | Multi-provider chat + agentic tool loop |

## Notes & limits

- Tools run with a 6-iteration cap to prevent runaway loops.
- `read_page` truncates page text to ~8k characters to keep token use sane.
- The `.3mf` loader reads the `3D/3dmodel.model` mesh (vertices + triangles)
  via the system `unzip`; color/material extensions are ignored.
