<p align="center"><a href="README.md">English</a> · <a href="README.ru.md">Русский</a> · <a href="README.zh.md">简体中文</a> · <a href="README.ja.md">日本語</a></p>

<h1 align="center">🖌️ MacPaint Native</h1>
<p align="center"><b>Apple 1984 年原版 MacPaint 的现代 Mac 原生移植</b></p>

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

## ✨ 制作方式

MacPaint Native **不是模拟器**，而是一个全新的原生 macOS 应用，使用 Swift 依据计算机历史博物馆（Computer History Museum）公开的 Apple 历史 **MacPaint 1.3 源代码**（Pascal 与 68000 汇编）编写。移植借助 **OpenAI Codex** 完成：逐个例程研究原始代码，并以原生方式重新实现其行为——1 位页面位图、QuickDraw 风格的线条、形状与椭圆、工具面板、图案、菜单、对话框以及 MacPaint 文档格式。

原始资源（菜单、对话框、警告框、字符串、图案、帮助图片、图标和位图字体——`MacPaintNative/Resources` 中 140 多个文件）从历史档案中提取并在运行时加载，因此应用的外观和行为与 1984 年原版逐像素一致。

## 🧰 技术栈

| | |
|---|---|
| **语言** | Swift 5 |
| **界面** | AppKit（在 `NSView` 中自绘经典 1 位工作区，原生菜单栏镜像经典菜单） |
| **图形** | 自研 1 位 `Bitmap` 光栅引擎，提供 QuickDraw 风格图元（线、矩形、圆角矩形、椭圆、多边形、填充、图案） |
| **文字** | 原版 Macintosh 位图字体（`FONT`/`FOND` 资源），由 `BitmapText` 渲染 |
| **构建** | Xcode 项目，目标 `MacPaintNative`，macOS 15.0+，arm64 |
| **原始素材** | Apple MacPaint 1.3 源代码与资源（计算机历史博物馆） |
| **开发工具** | OpenAI Codex |

## 🎨 功能

### 工具——完整的原版面板（20 个）

| 工具 | 说明 |
|---|---|
| 套索 | 自由形状选区 |
| 矩形选框 | 拖动移动，⌥ 拖动复制，⌘ 拖动拉伸 |
| 抓手 | 在窗口内滚动页面 |
| 文字 | 位图文字：字体、字号、样式、对齐 |
| 油漆桶 | 用当前图案填充 |
| 喷枪 | 喷洒当前图案 |
| 画笔 | 可选笔刷形状，Brush Mirrors 对称 |
| 铅笔 | 1 像素手绘 |
| 直线 | 按所选线宽画线 |
| 橡皮擦 | 擦除为白色 |
| 矩形 · 填充矩形 | 描边或图案填充 |
| 圆角矩形 · 填充 | 描边或图案填充 |
| 椭圆 · 填充椭圆 | QuickDraw 风格椭圆 |
| 自由形状 · 填充 | 闭合的手绘形状 |
| 多边形 · 填充多边形 | 点击添加顶点，回到起点闭合 |

修饰键与原版一致：**Shift** 约束线条和形状，**Option** 用当前图案描边，**Option 拖动** 复制选区，**⌘ 拖动** 拉伸选区。

### 菜单

| Menu | |
|---|---|
| **File** | New · Open · Close · Save · Save As · Revert · Print Draft · Print Final · Print Catalog · Quit |
| **Edit** | Undo ⌘Z · Cut ⌘X · Copy ⌘C · Paste ⌘V · Clear · Invert · Fill · Trace Edges ⌘E · Flip Horizontal · Flip Vertical · Rotate |
| **Goodies** | Grid · FatBits · Show Page · Edit Pattern · Brush Shape · Brush Mirrors · Introduction · Short Cuts |
| **Font** | Chicago · Geneva · New York · Monaco · Times · Helvetica · Courier |
| **FontSize** | 9 · 10 · 12 · 14 · 18 · 24 · 36 · 48 · 72 |
| **Style** | Plain ⌘P · Bold ⌘B · Italic ⌘I · Underline ⌘U · Outline ⌘O · Shadow ⌘S · Align Left ⌘L / Middle ⌘M / Right ⌘R |

### 更多

- 打开和保存真正的 **MacPaint 文档**（`.mac`、`.pntg`、`.paint`、`.mpnt`，类型 `PNTG`），包括 MacBinary 封装文件和带自定义图案的文档
- 经典图案面板及 **Edit Pattern**、线宽面板、**Brush Shape** 与 **Brush Mirrors** 对话框
- **FatBits** 放大、**Grid** 网格、**Show Page** 整页预览
- Undo、Invert、Fill、Trace Edges（Shift 添加阴影）、Flip、Rotate
- 与系统**剪贴板**集成（图片和文字）
- **崩溃恢复**：未保存的作品会被快照，并在下次启动时恢复
- 来自 1984 年资源的原版对话框、警告框和帮助画面（*Introduction*、*Short Cuts*）
- 通过 macOS 打印：Print Draft、Print Final 和 Print Catalog

## 🧪 Mod

**MacPaint Native Mod** 是一个可选的实验性版本，在忠实移植的基础上增加了一些现代功能。Mod 代码**只存在于 [`mod`](https://github.com/imedfan/MacPaint/tree/mod) 分支**，永远不会合并到 `main`——`main` 始终是纯粹的移植版。

### 获取

- **预编译版本：** 从发布版 [v0.1.0](https://github.com/imedfan/MacPaint/releases/tag/v0.1.0) 下载 [MacPaint-Native-Mod-0.1-b-arm64.dmg](https://github.com/imedfan/MacPaint/releases/download/v0.1.0/MacPaint-Native-Mod-0.1-b-arm64.dmg)（Apple Silicon）。
- **从源码构建：** 按照[构建与运行](#️-构建与运行)中的相同步骤构建 `mod` 分支：

```bash
git clone -b mod https://github.com/imedfan/MacPaint.git   # or: git checkout mod
cd MacPaint/MacPaintNative
xcodebuild -project MacPaintNative.xcodeproj -target MacPaintNative -configuration Release build
open build/Release/MacPaintNative.app
```

### 启用

Mod **默认关闭**，应用的行为与原版完全一致。要启用它们：

1. 打开 **About MacPaint**，勾选 **Enable mods**（位于 *Native ARM64 adaptation* 下）。
2. 会出现一个新的 **Mods** 菜单，位于 **Style** 之后的最后一个：*Macintosh 128K…*、*AI control*、*AI Connection…*（在相关时还有 *Next Document*、*Stop AI Drawing* 和 *Cancel Operation*）。

该设置按应用保存（不保存在图画中，也不写入 MacPaint 文件格式）。取消勾选 **Enable mods** 会隐藏菜单、停止 AI 绘图并关闭 MCP 连接。

### 原版模式——Macintosh 128K

想法是：移植版在 Apple Silicon 上瞬间运行，但 MacPaint 是为一台拥有 128 KB 内存和软驱的 1984 年机器设计的。**Mods → Macintosh 128K…** 重现了这些限制的*近似效果*，让你感受程序最初的表现。它不是 68000 或 System 模拟器，也没有按真实硬件校准。

勾选 *Enable Macintosh 128K mode* 后的变化：

- **虚拟内存预算**——模拟的堆（128 KB 减去屏幕、栈、两个工作缓冲区以及系统/程序保留区）。放不下的操作会被拒绝并提示 *“Macintosh 128K: Not enough memory”*；面板显示堆的空闲字节数。对整个连通区域的大面积填充可能会被拒绝。
- **操作与软驱延迟**（默认开启）——打开/保存 ≈ 0.9 秒，滚动/翻页 ≈ 0.3 秒，粘贴、油漆桶、Fill、Trace Edges、Rotate、Flip ≈ 0.4 秒，并提供 *Cancel Operation* 命令。
- **经典鼠标加速（近似）**——可选地将快速鼠标移动加倍，作用于 macOS 已处理过的输入之上。
- 面板中显示的参考规格：*512 × 342 screen · 576 × 720 page · 1-bit pixels*。

### MCP——让 AI 智能体来画

Mod 内置一个 [Model Context Protocol](https://modelcontextprotocol.io) 服务器，因此本地 AI 智能体（Codex、Cursor、Claude Code……）可以查看页面并在真正的 MacPaint 中作画。MacPaint 内部不需要 API 密钥——模型在你的客户端中运行。

- **传输方式：** STDIO。客户端启动内置的辅助程序 `MacPaint.app/Contents/MacOS/MacPaintMCP`（指向主可执行文件的链接；`MacPaintNative --mcp` 同样可用）。它通过本地 Unix 套接字（`/private/tmp/macpaint-mcp-<uid>/control.sock`；可用 `--socket <path>` 覆盖）与正在运行的应用通信。
- **开启：** Enable mods → **Mods → AI control**。**Mods → AI Connection…** 应显示 `Ready for local MCP clients.`
- **工具（10 个）：** `get_canvas`（页面 PNG + 状态）、`draw_batch`（1–128 个动作——stroke、line、polygon、rectangle、oval、fill、text——以 576 × 720 页面像素为单位，黑/白/灰，一个 Undo 步骤）、`undo`、`new_document`、`open_document`、`save_document`、`save_as`、`export_png`、`list_documents`、`switch_document`（最多 16 个打开的文档）。
- 批次绘制时，MacPaint 会显示进度和 **Stop** 按钮（也可按 Escape 或 **Mods → Stop AI Drawing**）；**Edit → Undo** 会撤销整个批次。除非传入 `"overwrite": true`，否则绝不会覆盖已有文件。

将下面的路径替换为你的应用所在位置（例如 `/Applications/MacPaint.app`，或源码构建的 `MacPaintNative/build/Release/MacPaintNative.app`）。

**Codex** — `~/.codex/config.toml`:

```toml
[mcp_servers.macpaint]
command = "/Applications/MacPaint.app/Contents/MacOS/MacPaintMCP"
tool_timeout_sec = 45
```

或 `codex mcp add macpaint -- /Applications/MacPaint.app/Contents/MacOS/MacPaintMCP`

**Cursor** — `~/.cursor/mcp.json` （全局）或 `.cursor/mcp.json` （项目）：

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

然后提出请求，例如：*“Use the macpaint MCP. Call get_canvas, then draw a house with a chimney, two windows and a tree on the right in one draw_batch.”* 完整指南（俄语）：`mod` 分支上的 [`MacPaintNative/AI-MCP-setup.md`](https://github.com/imedfan/MacPaint/blob/mod/MacPaintNative/AI-MCP-setup.md)。

## 🛠️ 构建与运行

**要求：** macOS 15 或更高版本、Apple Silicon（arm64）、带 Swift 5 的 Xcode。

```bash
git clone https://github.com/imedfan/MacPaint.git
cd MacPaint/MacPaintNative
xcodebuild -project MacPaintNative.xcodeproj -target MacPaintNative -configuration Release build
open build/Release/MacPaintNative.app
```

应用内置自检：

```bash
APP=build/Release/MacPaintNative.app/Contents/MacOS/MacPaintNative
"$APP" --verify-model /tmp/macpaint-model   # 无窗口的文档模型与光栅检查
"$APP" --verify /tmp/macpaint-ui            # 图形界面验证
```

## 📁 项目结构

```text
MacPaint/
├── COPYRIGHT.TXT                  # Apple 版权声明（仅限非商业用途）
├── MacPaintNative/
│   ├── Info.plist                 # 包信息、MacPaint 文档类型
│   ├── MacPaintNative.xcodeproj/
│   ├── Resources/                 # 原版 MacPaint 与 System 资源、图标
│   └── Sources/
│       ├── main.swift             # 入口、验证参数
│       ├── AppController.swift    # 菜单、文档、剪贴板、打印
│       ├── WorkspaceView.swift    # 经典工作区视图：面板、窗口、菜单
│       ├── PaintModel.swift       # 文档模型与工具逻辑
│       ├── Bitmap.swift, QuickDrawOval.swift   # 1 位光栅引擎、QuickDraw 椭圆
│       ├── BitmapText.swift       # 位图字体
│       ├── MacPaintFile.swift     # MacPaint 文件格式（+ MacBinary）
│       ├── ClassicResources.swift, ClassicDialogView.swift  # 资源加载、经典对话框
│       ├── PageOverview.swift     # Show Page
│       ├── PaintCatalog.swift, CatalogPrintView.swift, PrintRaster.swift  # 目录与打印
│       ├── RecoveryStore.swift    # 崩溃恢复
│       └── *Verification.swift    # 自检
└── docs/                          # GitHub Pages 网站
```

## ⚖️ 法律声明

- 这是一个**非官方、非商业的爱好者项目**，**与 Apple Inc. 无关，未获其认可或赞助**。
- **MacPaint**、Apple 和 Macintosh 是 Apple Inc. 的商标。
- MacPaint 原始源代码 **© 1984 Apple Inc.**，由 **[计算机历史博物馆](https://computerhistory.org/blog/macpaint-and-quickdraw-source-code/)** 提供，仅可依据博物馆许可用于非商业用途（见 [`COPYRIGHT.TXT`](COPYRIGHT.TXT)）。本项目以相同条款发布——禁止商业使用。
- 部分辅助材料依据 Executor 许可包含（`MacPaintNative/Resources/Executor-COPYING.txt`）。
- **如 Apple 或任何权利人提出异议，本仓库将立即删除。** 请通过 [GitHub Issues](https://github.com/imedfan/MacPaint/issues) 联系。

---

<p align="center">以 ❤️ 献给 1984 年的 Macintosh · <a href="https://imedfan.github.io/MacPaint/">imedfan.github.io/MacPaint</a></p>
