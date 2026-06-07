# EIN -- Emacs IPython Notebook (Jupyter 7.x fork)

[![build-status](https://github.com/millejoh/emacs-ipython-notebook/workflows/CI/badge.svg)](https://github.com/millejoh/emacs-ipython-notebook/actions)
[![melpa-dev](https://melpa.org/packages/ein-badge.svg)](http://melpa.org/#/ein)

[Jupyter](http://jupyter.org) client for Emacs. Supports all Jupyter kernels.

This is a fork of [dickmao/emacs-ipython-notebook](https://github.com/dickmao/emacs-ipython-notebook) with patches for **Jupyter Server >= 2.x (and the modern `jupyter server` CLI)**. The upstream EIN package v20250307.1731 is no longer maintained for modern Jupyter, and many core features (login, version detection, undo, session creation) silently break on a current Jupyter install. This fork restores usability.

## Install

Either install from MELPA (which will track the upstream, unfixed version) or clone this repo:

```sh
git clone https://github.com/<your-fork>/emacs-ipython-notebook.git
cd emacs-ipython-notebook
make install
```

Or load the `lisp/*.el` files directly from your init file.

## What this fork fixes

### 1. Version detection for Jupyter Server (no more `api/spec.yaml`)

Jupyter Server 2.x removed `api/spec.yaml`. EIN's `ein:query-notebook-api-version` was failing on the first call, so every subsequent API request misclassified the server.

- **File:** `lisp/ein-query.el`
- Try `GET /api/status` first; fall back to `api/spec.yaml` if absent.
- Normalize the Jupyter Server version to `"6"` so existing version-branched code paths still work.
- Add predicate `ein:query-api-version--jupyter-server-p`.

### 2. Session creation without deprecated `type` field

Jupyter Server deprecated the `type` field in `POST /api/sessions`; sending it now causes a 400.

- **File:** `lisp/ein-kernel.el`
- For Jupyter Server, omit `(type . "notebook")` from the session body.
- Bump the WebSocket protocol envelope from `"5.0"` to `"5.3"`.

### 3. `ein:login` no longer prompts for a password on a token-less server

On a server with `c.ServerApp.token = ''` (no auth) EIN used to:

1. Try to crib the token by shelling out to `jupyter list --json`. If the JSON parse or URL match failed, the crib returned `(nil nil)`.
2. Fall through to the legacy `/login` HTML-form login loop, which issued `GET /login`, got a 404 (the endpoint is gone in Jupyter Server), and prompted for a password via `read-passwd`.

The fix:

- **File:** `lisp/ein-jupyter.el` — `ein:jupyter-crib-token` now matches by URL **or** port, and uses `lax-plist-get` so the `cl-destructuring-bind`-on-hash-table bug introduced during the rewrite doesn't silently drop every result.
- **File:** `lisp/ein-notebooklist.el` — `ein:notebooklist-login` now treats `nil` token (crib unavailable) the same as a known Jupyter Server: skip `/login` and call `ein:notebooklist-open*` directly. `ein:notebooklist-open*` performs the version detection via `GET /api/status` over HTTP, so no shell-out is required.

### 4. Crippled-undo fix

Modern Emacs (26+) inserts `(t . 0)` undo boundaries after every command. EIN's `ein:worksheet--which-cell-hook` did not filter them, causing the `ein:%which-cell%` bookkeeping to drift from `buffer-undo-list`. After a few edits the difference crossed the abort threshold and `ein:worksheet--jigger-undo-list` raised an error, permanently disabling undo in the worksheet buffer.

- **File:** `lisp/ein-worksheet.el`
- Filter `(t . 0)` (and marker) entries in `ein:worksheet--which-cell-hook` so they no longer count.
- Replace the abort-and-disable path in `ein:worksheet--jigger-undo-list` with a resync: pad or trim `ein:%which-cell%` to match `buffer-undo-list`.

### 5. Default subcommand is `server`, not `notebook`

- **File:** `lisp/ein-jupyter.el`
- `ein:jupyter-server-use-subcommand` defaults to `"server"` (was `"notebook"`).

## Configuration tips

If you launch Jupyter with `c.ServerApp.token = ''` (no auth), you may also want:

```elisp
(setq ein:jupyter-cannot-find-jupyter t)   ; use exec-path-from-shell if jupyter isn't on Emacs' PATH
```

Otherwise, even though the login path no longer requires the crib, the "default kernel" crib (`ein:jupyter-default-kernel`) and the "running servers" crib still shell out and will warn `cannot find jupyter`.

## Known issues

- **Broken symlinks**: Jupyter Server's `fileio.py` returns `400 Cannot read non-file` for broken symlinks. EIN faithfully forwards the error. Fix the symlink on disk.
- **Polymode compatibility** with newer `polymode` releases is not guaranteed; this fork does not change polymode usage.

## License

GPLv3. See `LICENSE`.
