<p align="center"><a href="README.md">English</a> · <a href="README.ru.md">Русский</a> · <a href="README.zh.md">简体中文</a> · <a href="README.ja.md">日本語</a></p>

<h1 align="center">🖌️ MacPaint Native</h1>
<p align="center"><b>A native port of Apple's original 1984 MacPaint for modern Macs</b></p>

<p align="center">
  <img alt="macOS 15+" src="https://img.shields.io/badge/macOS-15%2B-000000?logo=apple&logoColor=white">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-arm64-555555">
  <img alt="Swift 5" src="https://img.shields.io/badge/Swift-5-F05138?logo=swift&logoColor=white">
  <img alt="AppKit" src="https://img.shields.io/badge/UI-AppKit-1575F9">
  <img alt="Built with Codex" src="https://img.shields.io/badge/built%20with-OpenAI%20Codex-412991?logo=openai&logoColor=white">
  <img alt="Non-commercial" src="https://img.shields.io/badge/license-non--commercial-lightgrey">
  <a href="https://imedfan.github.io/MacPaint/"><img alt="Website" src="https://img.shields.io/badge/website-imedfan.github.io%2FMacPaint-brightgreen"></a>
</p>

<p align="center"><a href="https://imedfan.github.io/MacPaint/"><b>🌐 imedfan.github.io/MacPaint</b></a></p>

<p align="center"><img src="docs/screenshot.png" alt="MacPaint Native" width="720"></p>

## ✨ How it was made

MacPaint Native is **not an emulator**. It is a new native macOS application written in Swift from Apple's historical **MacPaint 1.3 source code** (Pascal and 68000 assembly), released by the Computer History Museum. The port was built with **OpenAI Codex**: the original source was studied routine by routine and its behavior re-implemented natively — the 1‑bit page bitmap, QuickDraw-style lines, shapes and ovals, the tool palette, patterns, menus, dialogs and the MacPaint document format.

The original resources (menus, dialogs, alerts, strings, patterns, help pictures, icons and bitmap fonts — 140+ files in `MacPaintNative/Resources`) are extracted from the historical archive and loaded at runtime, so the app looks and behaves like the 1984 original, pixel for pixel.

## 🧰 Tech stack

| | |
|---|---|
| **Language** | Swift 5 |
| **UI** | AppKit (custom `NSView` rendering of the classic 1‑bit workspace, native macOS menu bar mirrored from the classic menus) |
| **Graphics** | Own 1‑bit `Bitmap` raster engine with QuickDraw-style primitives (lines, rects, round rects, ovals, polygons, flood fill, patterns) |
| **Text** | Original Macintosh bitmap fonts (`FONT`/`FOND` resources) rendered by `BitmapText` |
| **Build** | Xcode project, target `MacPaintNative`, macOS 15.0+, arm64 |
| **Source material** | Apple MacPaint 1.3 source and resources (Computer History Museum) |
| **Made with** | OpenAI Codex |

## 🎨 Features

### Tools — the full original palette (20)

| Tool | Description |
|---|---|
| Lasso | Free-form selection |
| Selection rectangle | Rectangular marquee; drag to move, ⌥-drag to duplicate, ⌘-drag to stretch |
| Grabber | Scroll the page inside the window |
| Text | Bitmap text with font, size, style and alignment |
| Paint bucket | Flood fill with the current pattern |
| Spray can | Spray the current pattern |
| Paintbrush | Selectable brush shapes, Brush Mirrors symmetry |
| Pencil | 1‑pixel freehand drawing |
| Line | Lines in the selected line width |
| Eraser | Erase to white |
| Rectangle · Filled rectangle | Outlined or pattern-filled |
| Rounded rectangle · Filled | Outlined or pattern-filled |
| Oval · Filled oval | QuickDraw-style ovals |
| Freehand shape · Filled | Closed free-form shapes |
| Polygon · Filled polygon | Click to add vertices, close on the first point |

Modifiers follow the original: **Shift** constrains lines and shapes, **Option** draws outlines with the current pattern, **Option-drag** duplicates a selection, **⌘-drag** stretches it.

### Menus

| Menu | |
|---|---|
| **File** | New · Open · Close · Save · Save As · Revert · Print Draft · Print Final · Print Catalog · Quit |
| **Edit** | Undo ⌘Z · Cut ⌘X · Copy ⌘C · Paste ⌘V · Clear · Invert · Fill · Trace Edges ⌘E · Flip Horizontal · Flip Vertical · Rotate |
| **Goodies** | Grid · FatBits · Show Page · Edit Pattern · Brush Shape · Brush Mirrors · Introduction · Short Cuts |
| **Font** | Chicago · Geneva · New York · Monaco · Times · Helvetica · Courier |
| **FontSize** | 9 · 10 · 12 · 14 · 18 · 24 · 36 · 48 · 72 |
| **Style** | Plain ⌘P · Bold ⌘B · Italic ⌘I · Underline ⌘U · Outline ⌘O · Shadow ⌘S · Align Left ⌘L / Middle ⌘M / Right ⌘R |

### More

- Opens and saves real **MacPaint documents** (`.mac`, `.pntg`, `.paint`, `.mpnt`, type `PNTG`), including MacBinary-wrapped files and documents with custom patterns
- Classic pattern palette with **Edit Pattern**, line-width palette, **Brush Shape** and **Brush Mirrors** dialogs
- **FatBits** zoom, **Grid**, **Show Page** overview of the full page
- Undo, Invert, Fill, Trace Edges (Shift adds a shadow), Flip, Rotate
- System **clipboard** integration for pictures and text
- **Crash recovery**: unsaved work is snapshotted and offered again on the next launch
- Original dialogs, alerts and help screens (*Introduction*, *Short Cuts*) rendered from the 1984 resources
- Printing through macOS: Print Draft, Print Final and Print Catalog

## 🧪 Mod

**MacPaint Native Mod** is an optional, experimental build that adds a few modern extras on top of the faithful port. The mod code lives **only in the [`mod`](https://github.com/imedfan/MacPaint/tree/mod) branch** and is never merged into `main` — `main` stays the pure port.

### Get it

- **Prebuilt:** download [MacPaint-Native-Mod-0.1-b-arm64.dmg](https://github.com/imedfan/MacPaint/releases/download/v0.1.0/MacPaint-Native-Mod-0.1-b-arm64.dmg) from release [v0.1.0](https://github.com/imedfan/MacPaint/releases/tag/v0.1.0) (Apple Silicon).
- **From source:** build the `mod` branch with the same steps as in [Build & run](#️-build--run):

```bash
git clone -b mod https://github.com/imedfan/MacPaint.git   # or: git checkout mod
cd MacPaint/MacPaintNative
xcodebuild -project MacPaintNative.xcodeproj -target MacPaintNative -configuration Release build
open build/Release/MacPaintNative.app
```

### Enable it

Mods are **off by default** and the app behaves exactly like the original. To turn them on:

1. Open **About MacPaint** and check **Enable mods** (under *Native ARM64 adaptation*).
2. A new **Mods** menu appears, last after **Style**: *Macintosh 128K…*, *AI control*, *AI Connection…* (plus *Next Document*, *Stop AI Drawing* and *Cancel Operation* when relevant).

The setting is stored per app (not in the drawing or the MacPaint file format). Unchecking **Enable mods** hides the menu, stops AI drawing and closes the MCP connection.

### Original mode — Macintosh 128K

The idea: the port runs instantly on Apple Silicon, but MacPaint was designed around a 1984 machine with 128 KB of RAM and a floppy drive. **Mods → Macintosh 128K…** brings back an *approximation* of those limits so you can feel how the program originally behaved. It is not a 68000 or System emulator and is not calibrated to real hardware.

What it changes when *Enable Macintosh 128K mode* is checked:

- **Virtual memory budget** — a simulated heap (128 KB minus screen, stack, two working buffers and system/program reserve). Operations that would not fit are refused with *“Macintosh 128K: Not enough memory”*; the panel shows free heap bytes. Large fills of a whole connected area can be refused.
- **Operation and floppy delays** (on by default) — open/save ≈ 0.9 s, scrolling/page ≈ 0.3 s, paste, paint bucket, Fill, Trace Edges, Rotate, Flip ≈ 0.4 s, with a *Cancel Operation* command.
- **Classic mouse acceleration (approximate)** — optional doubling of fast mouse movement, applied on top of input already processed by macOS.
- Reference spec shown in the panel: *512 × 342 screen · 576 × 720 page · 1-bit pixels*.

### MCP — let AI agents draw

The mod includes a [Model Context Protocol](https://modelcontextprotocol.io) server, so a local AI agent (Codex, Cursor, Claude Code, …) can look at the page and draw on it in real MacPaint. No API key is needed inside MacPaint — the model runs in your client.

- **Transport:** STDIO. The client launches the bundled helper `MacPaint.app/Contents/MacOS/MacPaintMCP` (a link to the main executable; `MacPaintNative --mcp` works too). It talks to the running app over a local Unix socket (`/private/tmp/macpaint-mcp-<uid>/control.sock`; override with `--socket <path>`).
- **Turn it on:** Enable mods → **Mods → AI control**. **Mods → AI Connection…** should say `Ready for local MCP clients.`
- **Tools (10):** `get_canvas` (page as PNG + state), `draw_batch` (1–128 actions — stroke, line, polygon, rectangle, oval, fill, text — in 576 × 720 page pixels, black/white/gray, one Undo step), `undo`, `new_document`, `open_document`, `save_document`, `save_as`, `export_png`, `list_documents`, `switch_document` (up to 16 open documents).
- While a batch draws, MacPaint shows progress and a **Stop** button (also Escape or **Mods → Stop AI Drawing**); **Edit → Undo** reverts the whole batch. Existing files are never overwritten unless `"overwrite": true` is passed.

Replace the path below with where your app lives (e.g. `/Applications/MacPaint.app`, or `MacPaintNative/build/Release/MacPaintNative.app` for a source build).

**Codex** — `~/.codex/config.toml`:

```toml
[mcp_servers.macpaint]
command = "/Applications/MacPaint.app/Contents/MacOS/MacPaintMCP"
tool_timeout_sec = 45
```

or `codex mcp add macpaint -- /Applications/MacPaint.app/Contents/MacOS/MacPaintMCP`

**Cursor** — `~/.cursor/mcp.json` (global) or `.cursor/mcp.json` (project):

```json
{
  "mcpServers": {
    "macpaint": {
      "type": "stdio",
      "command": "/Applications/MacPaint.app/Contents/MacOS/MacPaintMCP"
    }
  }
}
```

**Claude Code:**

```bash
claude mcp add --transport stdio --scope user macpaint -- /Applications/MacPaint.app/Contents/MacOS/MacPaintMCP
```

Then ask, for example: *“Use the macpaint MCP. Call get_canvas, then draw a house with a chimney, two windows and a tree on the right in one draw_batch.”* Full guide (in Russian): [`MacPaintNative/AI-MCP-setup.md`](https://github.com/imedfan/MacPaint/blob/mod/MacPaintNative/AI-MCP-setup.md) on the `mod` branch.

## 🛠️ Build & run

**Requirements:** macOS 15 or later, Apple Silicon (arm64), Xcode with Swift 5.

```bash
git clone https://github.com/imedfan/MacPaint.git
cd MacPaint/MacPaintNative
xcodebuild -project MacPaintNative.xcodeproj -target MacPaintNative -configuration Release build
open build/Release/MacPaintNative.app
```

The app also contains built-in self-checks:

```bash
APP=build/Release/MacPaintNative.app/Contents/MacOS/MacPaintNative
"$APP" --verify-model /tmp/macpaint-model   # headless document model & raster checks
"$APP" --verify /tmp/macpaint-ui            # graphical verification
```

## 📁 Project structure

```text
MacPaint/
├── COPYRIGHT.TXT                  # Apple copyright notice (non-commercial use)
├── MacPaintNative/
│   ├── Info.plist                 # bundle info, MacPaint document types
│   ├── MacPaintNative.xcodeproj/
│   ├── Resources/                 # original MacPaint & System resources, icon
│   └── Sources/
│       ├── main.swift             # entry point, verification flags
│       ├── AppController.swift    # menus, documents, clipboard, printing
│       ├── WorkspaceView.swift    # classic workspace view: palettes, window, menus
│       ├── PaintModel.swift       # document model and tool logic
│       ├── Bitmap.swift, QuickDrawOval.swift   # 1‑bit raster engine, QuickDraw ovals
│       ├── BitmapText.swift       # bitmap fonts
│       ├── MacPaintFile.swift     # MacPaint file format (+ MacBinary)
│       ├── ClassicResources.swift, ClassicDialogView.swift  # resource loading, classic dialogs
│       ├── PageOverview.swift     # Show Page
│       ├── PaintCatalog.swift, CatalogPrintView.swift, PrintRaster.swift  # catalog & printing
│       ├── RecoveryStore.swift    # crash recovery
│       └── *Verification.swift    # self-checks
└── docs/                          # GitHub Pages site
```

## ⚖️ Legal

- This is an **unofficial, non-commercial fan project**. It is **not affiliated with, endorsed by or sponsored by Apple Inc.**
- **MacPaint**, Apple and Macintosh are trademarks of Apple Inc.
- The original MacPaint source code is **© 1984 Apple Inc.**, courtesy of the **[Computer History Museum](https://computerhistory.org/blog/macpaint-and-quickdraw-source-code/)**, and is available only for non-commercial use under the museum's license (see [`COPYRIGHT.TXT`](COPYRIGHT.TXT)). This project is distributed under the same terms — no commercial use.
- Some helper material is included under the Executor license (`MacPaintNative/Resources/Executor-COPYING.txt`).
- **If Apple or any rights holder objects to this repository, it will be removed promptly.** Please get in touch through [GitHub Issues](https://github.com/imedfan/MacPaint/issues).

---

<p align="center">Made with ❤️ for the 1984 Macintosh · <a href="https://imedfan.github.io/MacPaint/">imedfan.github.io/MacPaint</a></p>
