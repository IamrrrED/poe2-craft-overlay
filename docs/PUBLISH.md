# Публикация на GitHub / Publishing to GitHub

## Что именно публикуется

Публикуется **только исходный код**, а не рабочая папка: сборки, профиль WebView2, `node_modules` и скачанные
кэши данных в репозиторий не попадают. Скрипт `tools/publish_github.ps1` собирает снимок по белому списку и
отказывается публиковать, если в нём оказался файл больше 50 МБ (значит список пора пересмотреть).

Проверенный снимок: **428 файлов, 17,2 МБ**.

| Входит | Не входит |
|---|---|
| `src/` — движок на Lua | `app/` — Electron-сборка (743 МБ) |
| `overlay/*.cs`, `overlay/Ui/` — панель | `overlay/bin`, `overlay/obj`, профиль `webview2-data` |
| `tools/` — рыночный скрипт, генераторы, проверки | `tools/cache/` — скачанные данные (регенерируются) |
| `mcp-market/lib` — клиент трейда | `node_modules` |
| `docs/*.md`, `docs/*.png` — отчёты и скриншоты | `runtime/`, `headless/bin` |
| `README.md`, `.gitignore`, `tests.ps1` | логи, `last_item.txt`, `craft_memory.lua`, пробники |

## Шаги

1. **Создайте пустой репозиторий** на GitHub: без README, без .gitignore, без лицензии (иначе первый push
   конфликтует). Запишите URL, например `https://github.com/USER/poe2-craft-overlay.git`.
2. **Проверьте снимок** (ничего не публикует):
   ```powershell
   powershell -ExecutionPolicy Bypass -File tools\publish_github.ps1 -DryRun
   ```
3. **Опубликуйте**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File tools\publish_github.ps1 -Remote https://github.com/USER/poe2-craft-overlay.git
   ```
   Скрипт сделает `git init`, первый коммит и `git push -u origin main`.

## Аутентификация

Скрипт пользуется **git-аутентификацией машины**, паролей не спрашивает и не хранит. Варианты:

- **HTTPS + токен**: при первом push git спросит логин и пароль — вместо пароля вставьте Personal Access Token
  с правом `repo`. Сохранить его можно через `git config --global credential.helper manager`.
- **SSH**: если на машине есть ключ и он добавлен в GitHub —
  `-Remote git@github.com:USER/poe2-craft-overlay.git`.
- **Токен в URL** (не сохраняется в конфиг, но остаётся в истории команд):
  `-Remote https://TOKEN@github.com/USER/REPO.git`.

Без одного из этих способов публикация невозможна: на машине сейчас **нет ни remote, ни `gh` CLI, ни токена,
ни SSH-ключа** — проверено.

## Варианты истории

- **Как в скрипте (по умолчанию):** один чистый коммит снимка. Простая история, ничего лишнего.
- **С полной историей проекта:** `git subtree split -P poe2craft -b poe2-public` в корне рабочей папки, затем
  push этой ветки. История содержит ~20 коммитов с осмысленными сообщениями, но в неё попадут и служебные
  файлы, которые уже были закоммичены.

## О чём стоит знать перед публикацией

- **Данные третьих лиц.** В `src/Data/` лежат таблицы, собранные из Path of Building, poe2db и трейда
  (`poe.ninja`). Это данные игры и сообщества; при публикации разумно указать источники (в README они
  перечислены) и не выдавать их за свои.
- **Лицензия.** Сейчас файла лицензии нет. Если проект открывается — стоит добавить (MIT проще всего), иначе
  формально «все права сохранены» и пользоваться кодом нельзя.
- **Игра и правила.** В README есть оговорка: проект неофициальный и не связан с GGG.

---

# English

## What gets published

Only the **source code**, never the working folder: build output, the WebView2 profile, `node_modules` and the
downloaded data caches stay out. `tools/publish_github.ps1` assembles a snapshot from an allow-list and refuses
to publish if any single file is above 50 MB (that would mean the list needs a look).

Verified snapshot: **428 files, 17.2 MB**.

| Included | Excluded |
|---|---|
| `src/` — the Lua engine | `app/` — the Electron build (743 MB) |
| `overlay/*.cs`, `overlay/Ui/` — the panel | `overlay/bin`, `overlay/obj`, the `webview2-data` profile |
| `tools/` — market script, generators, checks | `tools/cache/` — downloaded data (regenerable) |
| `mcp-market/lib` — the trade client | `node_modules` |
| `docs/*.md`, `docs/*.png` — reports and screenshots | `runtime/`, `headless/bin` |
| `README.md`, `.gitignore`, `tests.ps1` | logs, `last_item.txt`, `craft_memory.lua`, probes |

## Steps

1. **Create an empty repository** on GitHub: no README, no .gitignore, no licence (otherwise the first push
   conflicts). Note the URL, e.g. `https://github.com/USER/poe2-craft-overlay.git`.
2. **Check the snapshot** (publishes nothing):
   ```powershell
   powershell -ExecutionPolicy Bypass -File tools\publish_github.ps1 -DryRun
   ```
3. **Publish**:
   ```powershell
   powershell -ExecutionPolicy Bypass -File tools\publish_github.ps1 -Remote https://github.com/USER/poe2-craft-overlay.git
   ```
   The script runs `git init`, makes the first commit and `git push -u origin main`.

## Authentication

The script uses the machine's **git authentication**; it never asks for or stores a password. Options:

- **HTTPS + token**: git asks for a login and password on the first push — paste a Personal Access Token with the
  `repo` scope instead of a password. It can be remembered with
  `git config --global credential.helper manager`.
- **SSH**: if a key exists and is added to GitHub —
  `-Remote git@github.com:USER/poe2-craft-overlay.git`.
- **Token in the URL** (not stored in the config, but it stays in the command history):
  `-Remote https://TOKEN@github.com/USER/REPO.git`.

Without one of these, publishing is impossible: this machine currently has **no remote, no `gh` CLI, no token and
no SSH key** — verified.

## History options

- **As the script does (default):** one clean snapshot commit. Simple history, nothing extra.
- **With the project's full history:** `git subtree split -P poe2craft -b poe2-public` in the workspace root, then
  push that branch. The history has ~20 commits with meaningful messages, but it also contains service files
  that were committed along the way.

## Before you publish

- **Third-party data.** `src/Data/` holds tables assembled from Path of Building, poe2db and the trade site
  (`poe.ninja`). It is game and community data; the README lists the sources and they should not be presented as
  original work.
- **Licence.** There is no licence file yet. If the project is opened up, add one (MIT is simplest) — otherwise
  the default "all rights reserved" legally forbids reuse.
- **The game and its rules.** The README carries the disclaimer: unofficial, not affiliated with GGG.
