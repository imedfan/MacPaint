<p align="center"><a href="README.md">English</a> · <a href="README.ru.md">Русский</a> · <a href="README.zh.md">简体中文</a> · <a href="README.ja.md">日本語</a></p>

<h1 align="center">🖌️ MacPaint Native</h1>
<p align="center"><b>Нативный порт оригинального MacPaint 1984 года от Apple для современных Mac</b></p>

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

## ✨ Как это сделано

MacPaint Native — **не эмулятор**. Это новое нативное macOS‑приложение на Swift, написанное по историческому **исходному коду MacPaint 1.3** (Pascal и ассемблер 68000), опубликованному Музеем компьютерной истории (Computer History Museum). Порт создан с помощью **OpenAI Codex**: исходник разбирался процедура за процедурой, а поведение воспроизводилось нативно — 1‑битная страница, линии, фигуры и овалы в стиле QuickDraw, палитра инструментов, узоры, меню, диалоги и формат документов MacPaint.

Оригинальные ресурсы (меню, диалоги, алерты, строки, узоры, картинки справки, иконки и растровые шрифты — более 140 файлов в `MacPaintNative/Resources`) извлечены из исторического архива и загружаются во время работы, поэтому приложение выглядит и ведёт себя как оригинал 1984 года — пиксель в пиксель.

## 🧰 Технологии

| | |
|---|---|
| **Язык** | Swift 5 |
| **UI** | AppKit (собственная отрисовка классического 1‑битного рабочего стола в `NSView`, нативная строка меню повторяет классические меню) |
| **Графика** | Собственный 1‑битный растровый движок `Bitmap` с примитивами в стиле QuickDraw (линии, прямоугольники, скруглённые прямоугольники, овалы, многоугольники, заливка, узоры) |
| **Текст** | Оригинальные растровые шрифты Macintosh (ресурсы `FONT`/`FOND`), рендер — `BitmapText` |
| **Сборка** | Проект Xcode, таргет `MacPaintNative`, macOS 15.0+, arm64 |
| **Исходный материал** | Исходники и ресурсы Apple MacPaint 1.3 (Computer History Museum) |
| **Сделано с** | OpenAI Codex |

## 🎨 Возможности

### Инструменты — вся оригинальная палитра (20)

| Инструмент | Описание |
|---|---|
| Лассо | Выделение произвольной формы |
| Прямоугольное выделение | Перетаскивание — перемещение, ⌥ — копия, ⌘ — растяжение |
| Рука | Прокрутка страницы в окне |
| Текст | Растровый текст: шрифт, размер, стиль, выравнивание |
| Заливка | Заливка текущим узором |
| Баллончик | Распыление текущего узора |
| Кисть | Форма кисти и симметрия Brush Mirrors |
| Карандаш | Рисование линией в 1 пиксель |
| Линия | Линии выбранной толщины |
| Ластик | Стирание до белого |
| Прямоугольник · залитый | Контур или заливка узором |
| Скруглённый прямоугольник · залитый | Контур или заливка узором |
| Овал · залитый | Овалы в стиле QuickDraw |
| Произвольная фигура · залитая | Замкнутые фигуры от руки |
| Многоугольник · залитый | Вершины по клику, замыкание в первой точке |

Модификаторы как в оригинале: **Shift** ограничивает линии и фигуры, **Option** рисует контур текущим узором, **Option‑перетаскивание** дублирует выделение, **⌘‑перетаскивание** растягивает его.

### Меню

| Menu | |
|---|---|
| **File** | New · Open · Close · Save · Save As · Revert · Print Draft · Print Final · Print Catalog · Quit |
| **Edit** | Undo ⌘Z · Cut ⌘X · Copy ⌘C · Paste ⌘V · Clear · Invert · Fill · Trace Edges ⌘E · Flip Horizontal · Flip Vertical · Rotate |
| **Goodies** | Grid · FatBits · Show Page · Edit Pattern · Brush Shape · Brush Mirrors · Introduction · Short Cuts |
| **Font** | Chicago · Geneva · New York · Monaco · Times · Helvetica · Courier |
| **FontSize** | 9 · 10 · 12 · 14 · 18 · 24 · 36 · 48 · 72 |
| **Style** | Plain ⌘P · Bold ⌘B · Italic ⌘I · Underline ⌘U · Outline ⌘O · Shadow ⌘S · Align Left ⌘L / Middle ⌘M / Right ⌘R |

### Ещё

- Открывает и сохраняет настоящие **документы MacPaint** (`.mac`, `.pntg`, `.paint`, `.mpnt`, тип `PNTG`), включая файлы в MacBinary и документы со своими узорами
- Классическая палитра узоров с **Edit Pattern**, палитра толщины линий, диалоги **Brush Shape** и **Brush Mirrors**
- Увеличение **FatBits**, **Grid**, обзор всей страницы **Show Page**
- Undo, Invert, Fill, Trace Edges (Shift добавляет тень), Flip, Rotate
- Интеграция с системным **буфером обмена** (картинки и текст)
- **Восстановление после сбоя**: несохранённая работа сохраняется и предлагается при следующем запуске
- Оригинальные диалоги, алерты и экраны справки (*Introduction*, *Short Cuts*) из ресурсов 1984 года
- Печать через macOS: Print Draft, Print Final и Print Catalog

## 🧪 Мод

**MacPaint Native Mod** — необязательная экспериментальная сборка, которая добавляет к точному порту несколько современных возможностей. Код мода живёт **только в ветке [`mod`](https://github.com/imedfan/MacPaint/tree/mod)** и никогда не вливается в `main` — `main` остаётся чистым портом.

### Как получить

- **Готовая сборка:** скачайте [MacPaint-Native-Mod-0.1-b-arm64.dmg](https://github.com/imedfan/MacPaint/releases/download/v0.1.0/MacPaint-Native-Mod-0.1-b-arm64.dmg) из релиза [v0.1.0](https://github.com/imedfan/MacPaint/releases/tag/v0.1.0) (Apple Silicon).
- **Из исходников:** соберите ветку `mod` так же, как описано в разделе [Сборка и запуск](#️-сборка-и-запуск):

```bash
git clone -b mod https://github.com/imedfan/MacPaint.git   # or: git checkout mod
cd MacPaint/MacPaintNative
xcodebuild -project MacPaintNative.xcodeproj -target MacPaintNative -configuration Release build
open build/Release/MacPaintNative.app
```

### Как включить

Моды **по умолчанию выключены**, и приложение ведёт себя в точности как оригинал. Чтобы включить их:

1. Откройте **About MacPaint** и отметьте **Enable mods** (в блоке *Native ARM64 adaptation*).
2. Появится новое меню **Mods**, последнее после **Style**: *Macintosh 128K…*, *AI control*, *AI Connection…* (а также *Next Document*, *Stop AI Drawing* и *Cancel Operation*, когда они актуальны).

Настройка хранится на уровне приложения (а не в рисунке и не в формате файла MacPaint). Если снять **Enable mods**, меню скроется, рисование ИИ остановится, а MCP-соединение закроется.

### Оригинальный режим — Macintosh 128K

Идея: порт мгновенно работает на Apple Silicon, но MacPaint создавался для машины 1984 года со 128 КБ ОЗУ и дисководом. **Mods → Macintosh 128K…** возвращает *приближённую имитацию* этих ограничений, чтобы можно было почувствовать, как программа вела себя изначально. Это не эмулятор 68000 или System и не откалибровано по реальному железу.

Что меняется, когда отмечено *Enable Macintosh 128K mode*:

- **Бюджет виртуальной памяти** — имитируемая куча (128 КБ минус экран, стек, два рабочих буфера и резерв системы/программы). Операции, которые не помещаются, отклоняются с сообщением *“Macintosh 128K: Not enough memory”*; панель показывает свободные байты кучи. Крупные заливки целой связной области могут быть отклонены.
- **Задержки операций и дисковода** (включены по умолчанию) — открытие/сохранение ≈ 0,9 с, прокрутка/страница ≈ 0,3 с, вставка, заливка (paint bucket), Fill, Trace Edges, Rotate, Flip ≈ 0,4 с, с командой *Cancel Operation*.
- **Классическое ускорение мыши (приближённо)** — необязательное удвоение быстрых движений мыши поверх ввода, уже обработанного macOS.
- Справочные характеристики в панели: *512 × 342 screen · 576 × 720 page · 1-bit pixels*.

### MCP — пусть рисуют ИИ-агенты

Мод включает сервер [Model Context Protocol](https://modelcontextprotocol.io), поэтому локальный ИИ-агент (Codex, Cursor, Claude Code, …) может посмотреть на страницу и рисовать на ней в настоящем MacPaint. Внутри MacPaint API-ключ не нужен — модель работает в вашем клиенте.

- **Транспорт:** STDIO. Клиент запускает встроенный помощник `MacPaint.app/Contents/MacOS/MacPaintMCP` (ссылка на основной исполняемый файл; `MacPaintNative --mcp` тоже работает). Он общается с запущенным приложением через локальный Unix-сокет (`/private/tmp/macpaint-mcp-<uid>/control.sock`; переопределяется через `--socket <path>`).
- **Включение:** Enable mods → **Mods → AI control**. **Mods → AI Connection…** должно показывать `Ready for local MCP clients.`
- **Инструменты (10):** `get_canvas` (страница в PNG + состояние), `draw_batch` (1–128 действий — stroke, line, polygon, rectangle, oval, fill, text — в пикселях страницы 576 × 720, чёрный/белый/серый, один шаг Undo), `undo`, `new_document`, `open_document`, `save_document`, `save_as`, `export_png`, `list_documents`, `switch_document` (до 16 открытых документов).
- Пока пакет рисуется, MacPaint показывает прогресс и кнопку **Stop** (также Escape или **Mods → Stop AI Drawing**); **Edit → Undo** отменяет весь пакет целиком. Существующие файлы никогда не перезаписываются, если не передано `"overwrite": true`.

Замените путь ниже на место, где лежит ваше приложение (например, `/Applications/MacPaint.app` или `MacPaintNative/build/Release/MacPaintNative.app` для сборки из исходников).

**Codex** — `~/.codex/config.toml`:

```toml
[mcp_servers.macpaint]
command = "/Applications/MacPaint.app/Contents/MacOS/MacPaintMCP"
tool_timeout_sec = 45
```

или `codex mcp add macpaint -- /Applications/MacPaint.app/Contents/MacOS/MacPaintMCP`

**Cursor** — `~/.cursor/mcp.json` (глобально) или `.cursor/mcp.json` (проект):

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

Затем попросите, например: *“Use the macpaint MCP. Call get_canvas, then draw a house with a chimney, two windows and a tree on the right in one draw_batch.”* Полное руководство (на русском): [`MacPaintNative/AI-MCP-setup.md`](https://github.com/imedfan/MacPaint/blob/mod/MacPaintNative/AI-MCP-setup.md) в ветке `mod`.

## 🛠️ Сборка и запуск

**Требования:** macOS 15 или новее, Apple Silicon (arm64), Xcode со Swift 5.

```bash
git clone https://github.com/imedfan/MacPaint.git
cd MacPaint/MacPaintNative
xcodebuild -project MacPaintNative.xcodeproj -target MacPaintNative -configuration Release build
open build/Release/MacPaintNative.app
```

В приложение встроены самопроверки:

```bash
APP=build/Release/MacPaintNative.app/Contents/MacOS/MacPaintNative
"$APP" --verify-model /tmp/macpaint-model   # проверки модели и растра без окна
"$APP" --verify /tmp/macpaint-ui            # графическая проверка
```

## 📁 Структура проекта

```text
MacPaint/
├── COPYRIGHT.TXT                  # уведомление Apple (некоммерческое использование)
├── MacPaintNative/
│   ├── Info.plist                 # данные бандла, типы документов
│   ├── MacPaintNative.xcodeproj/
│   ├── Resources/                 # оригинальные ресурсы MacPaint и System, иконка
│   └── Sources/
│       ├── main.swift             # точка входа, флаги проверки
│       ├── AppController.swift    # меню, документы, буфер обмена, печать
│       ├── WorkspaceView.swift    # классический рабочий стол: палитры, окно, меню
│       ├── PaintModel.swift       # модель документа и логика инструментов
│       ├── Bitmap.swift, QuickDrawOval.swift   # 1‑битный растр, овалы QuickDraw
│       ├── BitmapText.swift       # растровые шрифты
│       ├── MacPaintFile.swift     # формат файлов MacPaint (+ MacBinary)
│       ├── ClassicResources.swift, ClassicDialogView.swift  # загрузка ресурсов, классические диалоги
│       ├── PageOverview.swift     # Show Page
│       ├── PaintCatalog.swift, CatalogPrintView.swift, PrintRaster.swift  # каталог и печать
│       ├── RecoveryStore.swift    # восстановление после сбоя
│       └── *Verification.swift    # самопроверки
└── docs/                          # сайт GitHub Pages
```

## ⚖️ Правовая информация

- Это **неофициальный некоммерческий фанатский проект**. Он **не связан с Apple Inc., не одобрен и не спонсируется ею**.
- **MacPaint**, Apple и Macintosh — товарные знаки Apple Inc.
- Оригинальный исходный код MacPaint — **© 1984 Apple Inc.**, предоставлен **[Computer History Museum](https://computerhistory.org/blog/macpaint-and-quickdraw-source-code/)** и доступен только для некоммерческого использования по лицензии музея (см. [`COPYRIGHT.TXT`](COPYRIGHT.TXT)). Проект распространяется на тех же условиях — без коммерческого использования.
- Часть вспомогательных материалов включена по лицензии Executor (`MacPaintNative/Resources/Executor-COPYING.txt`).
- **Если Apple или другой правообладатель возражает против этого репозитория, он будет оперативно удалён.** Свяжитесь через [GitHub Issues](https://github.com/imedfan/MacPaint/issues).

---

<p align="center">Сделано с ❤️ для Macintosh 1984 года · <a href="https://imedfan.github.io/MacPaint/">imedfan.github.io/MacPaint</a></p>
