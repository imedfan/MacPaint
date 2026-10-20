# Подключить AI-рисование к MacPaint

Инструкция для локальной ветки `mod`. MacPaint должен работать на том же Mac, что и MCP-клиент.
Ключ модели внутри MacPaint не нужен. Запросы обрабатывает выбранный клиент.

## Включить управление

1. Соберите приложение из каталога `MacPaintNative` командой `bash Tools/build.sh`.
2. Откройте `Build/MacPaint.app`.
3. В About MacPaint установите **Enable mods**.
4. Выберите **Mods → AI control**. В **Mods → AI Connection...** должно появиться `Ready for local MCP clients.`.

Приложение запоминает обе настройки. Выключение **Enable mods** останавливает AI-рисование и закрывает подключение.
После повторного включения модов управление восстанавливается, если **AI control** был включён.
Один экземпляр MacPaint принимает команды. Выключите управление в другом экземпляре, если сокет занят.

Для текущего checkout команда MCP имеет такой путь:

```text
/Users/artem/Documents/dev/102658076_macpaint_acc/MacPaintNative/Build/MacPaint.app/Contents/MacOS/MacPaintMCP
```

Если перенесёте приложение в `/Applications`, замените путь во всех настройках на `/Applications/MacPaint.app/Contents/MacOS/MacPaintMCP`.
Клиент запускает helper сам. Открывать helper вручную не нужно.

## Подключить Cursor

Добавьте сервер в `~/.cursor/mcp.json`. Если файл уже содержит серверы, добавьте запись `macpaint` в существующий `mcpServers`.

```json
{
  "mcpServers": {
    "macpaint": {
      "type": "stdio",
      "command": "/Users/artem/Documents/dev/102658076_macpaint_acc/MacPaintNative/Build/MacPaint.app/Contents/MacOS/MacPaintMCP"
    }
  }
}
```

Перезагрузите MCP-сервер в настройках Cursor и разрешите его использование.
Для настройки только в этом проекте используйте `.cursor/mcp.json`.
Эти расположения и STDIO-поля описаны в [документации Cursor](https://cursor.com/docs/mcp).

## Подключить Codex

Выполните команду, если установлен Codex CLI:

```sh
codex mcp add macpaint -- /Users/artem/Documents/dev/102658076_macpaint_acc/MacPaintNative/Build/MacPaint.app/Contents/MacOS/MacPaintMCP
```

Либо добавьте запись в `~/.codex/config.toml`:

```toml
[mcp_servers.macpaint]
command = "/Users/artem/Documents/dev/102658076_macpaint_acc/MacPaintNative/Build/MacPaint.app/Contents/MacOS/MacPaintMCP"
tool_timeout_sec = 45
```

Перезапустите Codex или переподключите MCP-сервер в настройках.
Используйте локальную сессию на этом Mac. Серверу нужен доступ к локальному сокету приложения.
Синтаксис подключения приведён в [официальной документации OpenAI](https://developers.openai.com/codex/mcp).

## Подключить Claude Code

Выполните команду:

```sh
claude mcp add --transport stdio --scope user macpaint -- /Users/artem/Documents/dev/102658076_macpaint_acc/MacPaintNative/Build/MacPaint.app/Contents/MacOS/MacPaintMCP
```

Откройте Claude Code и выполните `/mcp`, чтобы проверить сервер `macpaint`.
Команда и область `user` описаны в [документации Claude Code](https://code.claude.com/docs/en/mcp).

## Нарисовать и изменить рисунок

Отправьте клиенту запрос:

> Используй MCP macpaint. Сначала посмотри get_canvas, затем нарисуй дом с трубой, двумя окнами и деревом справа. Размести рисунок в visible_rect. В конце покажи результат через get_canvas.

Затем отправьте:

> Сделай окна больше. Сначала сотри старые окна белым цветом, затем нарисуй новые. Выполни изменение одним draw_batch.

Для отмены нажмите **Edit → Undo**, Command-Z или попросите клиента вызвать `undo`.
MacPaint хранит один шаг отмены. Повторная отмена переключает тот же рисунок обратно.
Используйте `save_as` с абсолютным путём, чтобы сохранить обычный `.mac`, либо **File → Save As...**.

## Документы и экспорт

| Команда | Аргументы | Результат |
| --- | --- | --- |
| `new_document` | `{}` | Новая пустая страница; предыдущая остаётся открытой. |
| `open_document` | `{"path":"/absolute/Drawing.mac"}` | Открывает MAC в приложении. Для уже открытого пути переключается на его документ, сохраняя несохранённые правки. |
| `save_document` | `{}` или `{"path":"/absolute/Drawing.mac"}` | Сохраняет MAC, обновляет имя и сбрасывает dirty. Без пути сохраняет в текущий файл. |
| `save_as` | `{"path":"/absolute/Copy.mac"}` | Сохраняет MAC под новым именем и принимает этот путь как текущий. |
| `export_png` | `{"path":"/absolute/Drawing.png"}` | Экспортирует всю страницу 576 × 720; имя, dirty и Undo сохраняются. |
| `list_documents` | `{}` | Возвращает `active_document_id` и список `documents`: ID, title, path, dirty, can_undo, active. |
| `switch_document` | `{"document_id":"ID из списка"}` | Восстанавливает документ вместе с его Undo, палитрой, выделением и положением страницы. |

Команды создания, открытия и переключения возвращают состояние активного документа; сохранение и экспорт также возвращают `written_path`.
`get_canvas` содержит `document_id` и `document_path`, чтобы сопоставить страницу со списком.
В одной сессии можно открыть до 16 документов. ID действуют до закрытия документа или приложения.
Переключение также доступно через **Mods → Next Document**; **File → Close** закрывает текущий рисунок и показывает оставшийся.
При выходе приложение предлагает сохранить изменения во всех открытых документах.
Выключение модов останавливает MCP и сохраняет открытые рисунки в памяти.

Для `save_as`, экспорта и сохранения по новому пути существующий файл защищён от перезаписи.
Чтобы заменить его, явно передайте `"overwrite":true`. Обычный `save_document` в текущий файл обновляет его без этого флага.
Нельзя записать поверх файла другого открытого документа или экспортировать PNG поверх текущего MAC.
Родительская папка должна существовать. Неверный путь, повреждённый MAC, файл больше 1 МБ или ошибка записи возвращают ошибку без замены текущего документа.

Пример серии отдельных рисунков: `new_document` → `draw_batch` → `save_as` → `export_png`; повторите для следующего варианта.
Для возврата к предыдущему рисунку вызовите `list_documents` и `switch_document`.

Во время пакета MacPaint показывает прогресс и кнопку **Stop**. Escape и **Mods → Stop AI Drawing** тоже останавливают пакет.
Завершённые действия остаются на странице и отменяются одним Undo.
Если запрос оборвался или истёк тайм-аут, вызовите `get_canvas` перед повтором рисования.

## Проверить подключение

В клиенте должны появиться десять инструментов: `get_canvas`, `draw_batch`, `undo`, `new_document`, `open_document`, `save_document`, `save_as`, `export_png`, `list_documents`, `switch_document`.
После обновления приложения переподключите MCP-сервер, чтобы клиент перечитал список инструментов.
При выключенном управлении список инструментов остаётся доступным, а обращения к рисунку возвращают ошибку с инструкцией включения.

Для проверки без настройки клиентов запустите из `MacPaintNative`:

```sh
bash Tools/build.sh Build/Verification/MacPaint.app
mkdir -p /private/tmp/macpaint-ai-verification
open -n -W Build/Verification/MacPaint.app --args --verify-ai /private/tmp/macpaint-ai-verification
```

Проверки запускают настоящий встроенный helper через STDIO, рисуют в тестовом окне и используют отдельные настройки и сокет.
Проверяются создание и переключение документов при 1x/2x, чтение/запись MAC, PNG, независимый Undo, dirty, ошибочные пути и защита от перезаписи.
Результаты находятся в `AI-Control.json`, `Mods.json` и PNG в указанном временном каталоге.
Для проверки исходного поведения используйте `bash Tools/verify.sh`.

Текст поддерживает исходные bitmap-шрифты и набор Mac Roman. Для подписей используйте латиницу.
Режим Macintosh 128K может отклонить крупный пакет. Заливка всей связной области требует больше его виртуальной памяти.
Для такого рисунка выключите профиль 128K либо замените заливку заполненной фигурой.
