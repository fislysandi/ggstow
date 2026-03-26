;;; ggstow/cli.scm — Argument parsing and command dispatch

(define-module (ggstow cli)
  #:use-module (ggstow plan)
  #:use-module (ggstow fs)
  #:use-module (ggstow conflict)
  #:use-module (ggstow manifest)
  #:use-module (ggstow variables)
  #:use-module (ice-9 getopt-long)
  #:export (ggstow-main))

;;; ---------------------------------------------------------------------------
;;; Option spec
;;; ---------------------------------------------------------------------------

(define option-spec
  '((help       (single-char #\h) (value #f))
    (version    (single-char #\v) (value #f))
    (config     (single-char #\c) (value #t))
    (dry-run                      (value #f))
    (overwrite  (single-char #\f) (value #f))
    (output     (single-char #\o) (value #t))
    (verbose                      (value #f))))

(define *version* "0.1.0-dev")

;;; ---------------------------------------------------------------------------
;;; Help text
;;; ---------------------------------------------------------------------------

(define (print-help)
  (display "\
ggstow — GNU Stow with superpowers (Guile Scheme)

Usage:
  ggstow <command> [options]

Commands:
  plan          Compute and display the symlink graph (no changes)
  apply         Create symlinks (use --dry-run to preview)
  status        Show current link state (active / broken / unmanaged)
  rollback      Remove all managed symlinks
  doctor        Diagnose broken links and environment issues
  export-guix   Emit a Guix Home home-files-service-type alist

Options:
  -c, --config=FILE    Path to ggstow config file (default: .ggstow.scm)
      --dry-run        Preview changes without touching disk
  -f, --overwrite      Overwrite existing files/links
  -o, --output=FILE    Output file for export-guix (default: stdout)
      --verbose        Verbose output
  -h, --help           Show this help
  -v, --version        Show version

Variable substitution:
  Directory names using %VAR% syntax are resolved to OS-specific paths
  via plugin scripts in the 'variables/' directory (or config file).

Examples:
  ggstow plan
  ggstow apply --dry-run
  ggstow apply --overwrite
  ggstow export-guix --output=home-files.scm
"))

;;; ---------------------------------------------------------------------------
;;; Dispatch
;;; ---------------------------------------------------------------------------

(define (ggstow-main args)
  (let* ((opts    (getopt-long args option-spec #:stop-at-first-non-option #t))
         (rest    (option-ref opts '() '()))
         (help?   (option-ref opts 'help #f))
         (ver?    (option-ref opts 'version #f))
         (command (if (null? rest) #f (car rest))))

    (cond
     (help?   (print-help) (exit 0))
     (ver?    (format #t "ggstow ~a~%" *version*) (exit 0))
     ((not command)
      (display "ggstow: no command given. Try --help.\n" (current-error-port))
      (exit 1))
     (else
      (dispatch command opts)))))

(define (dispatch command opts)
  (let ((dry-run?  (option-ref opts 'dry-run  #f))
        (overwrite? (option-ref opts 'overwrite #f))
        (verbose?  (option-ref opts 'verbose  #f))
        (config    (option-ref opts 'config   ".ggstow.scm"))
        (output    (option-ref opts 'output   #f)))
    (cond
     ((string=? command "plan")
      (cmd-plan config verbose?))
     ((string=? command "apply")
      (cmd-apply config dry-run? overwrite? verbose?))
     ((string=? command "status")
      (cmd-status config verbose?))
     ((string=? command "rollback")
      (cmd-rollback config dry-run? verbose?))
     ((string=? command "doctor")
      (cmd-doctor config verbose?))
     ((string=? command "export-guix")
      (cmd-export-guix config output))
     (else
      (format (current-error-port) "ggstow: unknown command '~a'. Try --help.\n" command)
      (exit 1)))))

;;; ---------------------------------------------------------------------------
;;; Command implementations (thin wrappers — logic lives in modules)
;;; ---------------------------------------------------------------------------

(define (cmd-plan config verbose?)
  (let ((plan (compute-plan config)))
    (display-plan plan verbose?)))

(define (cmd-apply config dry-run? overwrite? verbose?)
  (let* ((plan      (compute-plan config))
         (conflicts (detect-conflicts plan)))
    (if (and (not (null? conflicts)) (not overwrite?))
        (begin
          (display-conflicts conflicts)
          (exit 1))
        (apply-plan plan dry-run? overwrite? verbose?))))

(define (cmd-status config verbose?)
  (display-status (compute-plan config) verbose?))

(define (cmd-rollback config dry-run? verbose?)
  (rollback-plan (compute-plan config) dry-run? verbose?))

(define (cmd-doctor config verbose?)
  (run-doctor config verbose?))

(define (cmd-export-guix config output)
  (let ((alist (plan->guix-alist (compute-plan config))))
    (if output
        (call-with-output-file output
          (lambda (port) (write-guix-alist alist port)))
        (write-guix-alist alist (current-output-port)))))
