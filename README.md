# ggstow

**GNU Stow with superpowers** — a declarative dotfile symlink manager written in Guile Scheme.

Inspired by [GNU Stow](https://www.gnu.org/software/stow/) and [Tuckr](https://github.com/RaphGL/Tuckr). Designed to integrate natively with [Guix Home](https://guix.gnu.org/manual/en/html_node/Home-Configuration.html).

## Features

- **`%VARIABLE%` path resolution** — directory names like `%NU_HOME%` expand to OS-specific paths
- **OS-suffix filtering** — packages named `tool_windows` / `tool_linux` / `tool_macos` only link on that OS
- **`.ggstow-ignore`** — per-package exclusion file
- **Conflict detection** — reports collisions before touching disk
- **Dry-run mode** — preview all changes with `--dry-run`
- **`export-guix`** — emit a `home-files-service-type` alist for Guix Home
- **Cross-platform links** — symlinks on Linux/macOS, junctions + fallback copy on Windows

## Status

Early development. Currently replaces [nutuck](https://github.com/fislysandi/nutuck) as the symlink manager for [fislysandi/dotfiles](https://github.com/fislysandi/dotfiles).

## Usage

```sh
# Preview what would be linked
guile ggstow.scm plan

# Create symlinks
guile ggstow.scm apply

# Dry run
guile ggstow.scm apply --dry-run

# Check current state
guile ggstow.scm status

# Diagnose broken links
guile ggstow.scm doctor

# Export a Guix Home files alist
guile ggstow.scm export-guix --output=home-files.scm
```

## Directory Structure

```
Configs/
  git/              # package: git (all platforms)
  nushell/
    %NU_HOME%/      # %VAR% expands to ~/.config/nushell (Linux/macOS)
      config.nu
  powershell_windows/  # only linked on Windows
    ...
```

## Project Structure

```
ggstow.scm          # CLI entry point
ggstow/
  cli.scm           # argument parsing, command dispatch
  plan.scm          # compute symlink graph from Configs/
  fs.scm            # filesystem abstraction (symlink/junction/copy)
  conflict.scm      # collision detection
  variables.scm     # %VAR% resolution
  manifest.scm      # export-guix output
```

## Requirements

- [GNU Guile](https://www.gnu.org/software/guile/) 3.0+
- On Windows: Developer Mode enabled (for symlinks) or Administrator (for junctions)
