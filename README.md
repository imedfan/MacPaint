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
