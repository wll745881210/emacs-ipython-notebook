# EIN (Emacs IPython Notebook) — Agent Navigation

## Build & Test

- **Install deps**: `cask install` (requires Cask: https://cask.readthedocs.io)
- **Compile (strict)**: `make test-compile` — byte-compiles all `lisp/*.el` with `byte-compile-error-on-warn`. MUST pass before committing.
- **Package**: `make dist` — creates tarball via `cask package` in `dist/`.
- **Lint** (MUST do before any MR): `make test-compile` — the only verification command.
- **Install locally**: `make install` — builds tar and installs via package.el.

`test/`, `features/`, and `tools/` directories have been removed. No unit/integration tests remain. Agents MUST NOT attempt to run them.

## Constraints

- **AGENTS.md, README.md, lisp/*.el** — agents MAY edit these.
- **Cask, Makefile, LICENSE, .gitignore** — agents MUST NOT modify.
- **Blocking processes** — agents MUST NOT start dev servers or watch modes.
- **External commands** — agents MUST NOT shell out to `jupyter`, `python`, or `npm` without user approval.
- **Git operations** — agents MUST NOT commit unless explicitly asked. `git push` requires `--force-with-lease` on `master` since history was rewritten.
- **Byte-compile** — always run `make test-compile` after editing any `.el` file to verify no warnings/errors.

## Architecture

EIN is an Emacs Lisp Jupyter notebook client (Emacs 26.1+, GPLv3). Uses EIEIO (Emacs native OOP) for data models, ewoc for cell rendering, `request.el` for HTTP, and `websocket.el` for WebSocket.

### Source Layout (`lisp/`)

| File | Role |
|------|------|
| `ein.el` | Entry point, package metadata, minor-mode definitions |
| `ein-classes.el` | EIEIO structs: `ein:$notebook`, `ein:basecell`/`ein:codecell`/`ein:textcell`, `ein:$kernel`, `ein:$kernelspec` |
| `ein-query.el` | HTTP layer via `request.el`. **Version detection** (patched: `/api/status` before `api/spec.yaml`) |
| `ein-kernel.el` | Kernel lifecycle, session POST, WS connect, message dispatch. **Protocol 5.3** |
| `ein-websocket.el` | Single WS multiplexer with in-band `:channel` tagging |
| `ein-notebook.el` | Notebook open/save, nbformat 3/4 parsing |
| `ein-notebooklist.el` | Notebook list buffer (widget-based). **Running Notebooks section** |
| `ein-jupyter.el` | Server subprocess management (`jupyter server` default) |
| `ein-cell.el` | Cell data model, MIME output rendering (text/html, images, text/plain) |
| `ein-worksheet.el` | Worksheet management, **undo fix** (filter `(t . 0)` boundaries, resync on mismatch) |
| `ein-contents-api.el` | Contents API v2 — session queries, file tree |
| `ein-utils.el` | URL normalization, UUID generation, JSON helpers |
| `ob-ein.el` | Org-babel integration |
| `poly-ein.el` | Polymode integration |

### Key Dependencies

Emacs 26.1, websocket 1.12, anaphora 1.0.4, request 0.3.3, deferred 0.5, polymode 0.2.2, dash 2.13.0, with-editor (any).

### History

Fork of `millejoh/emacs-ipython-notebook` with patches for Jupyter Server >= 2.x. Git history rewritten — only 5 commits remain (starting at `30fc54f8` as orphan root). Old upstream history (3372 commits stripped) is unreachable.
