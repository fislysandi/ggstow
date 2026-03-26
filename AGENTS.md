# Agent Instructions (AGENTS.md)

## Project Overview

**ggstow** — GNU Stow with superpowers. A Guile Scheme dotfile symlink manager.

- Entry point: `ggstow.scm`
- Modules: `ggstow/` (cli, plan, fs, conflict, variables, manifest)
- Language: Guile Scheme 3.0+
- Target platforms: Linux, macOS, Windows

## Module Responsibilities

| Module | Responsibility |
|---|---|
| `cli.scm` | Argument parsing, command dispatch |
| `plan.scm` | Scan Configs/, resolve %VAR%, build link list |
| `fs.scm` | Platform-aware link creation (symlink/junction/copy) |
| `conflict.scm` | Detect collisions before touching disk |
| `variables.scm` | %VARIABLE% resolution table |
| `manifest.scm` | export-guix output formatter |

## Code Style

- **Modules**: `(define-module (ggstow <name>) #:export (...))` — explicit exports only
- **Records**: `define-record-type` with typed constructors
- **Error handling**: `(error ...)` for hard failures, `format (current-error-port)` for warnings
- **No side effects at module load time** — all logic in functions
- **Commit messages**: `type(scope): description` — types: feat, fix, refactor, docs, test, chore

## Testing

Run tests with:
```sh
guile -L . tests/run.scm
```

## Key Design Decisions

- `%VARIABLE%` dirs in `Configs/` are resolved via `variables.scm` (not external scripts)
- `.ggstow-ignore` files list OS names to exclude (same convention as nutuck's `.nutuck-ignore`)
- `fs.scm` abstracts all link creation — never call `symlink` directly outside this module
- Windows: directory junctions first, symlinks if Developer Mode, copy as last resort
