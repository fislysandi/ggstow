#!/usr/bin/env -S guile --no-auto-compile -e main -s
!#

;;; ggstow.scm — GNU Guile Stow with superpowers
;;;
;;; Entry point. Parses CLI arguments and dispatches to commands.
;;;
;;; Usage:
;;;   guile ggstow.scm plan    [--config=FILE]
;;;   guile ggstow.scm apply   [--config=FILE] [--dry-run] [--overwrite]
;;;   guile ggstow.scm status  [--config=FILE]
;;;   guile ggstow.scm rollback
;;;   guile ggstow.scm doctor
;;;   guile ggstow.scm export-guix [--output=FILE]

(add-to-load-path (dirname (current-filename)))

(use-modules (ggstow cli))

(define (main args)
  (ggstow-main args))
