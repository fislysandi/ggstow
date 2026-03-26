;;; ggstow/fs.scm — Filesystem abstraction layer
;;;
;;; Handles symlink creation, deletion, and status checks in a
;;; platform-aware way. On Windows: junctions for directories,
;;; symlinks where available, copies as fallback.

(define-module (ggstow fs)
  #:use-module (ice-9 format)
  #:export (create-link
            remove-link
            link-status))

;;; ---------------------------------------------------------------------------
;;; Platform detection
;;; ---------------------------------------------------------------------------

(define (windows?)
  (string-contains (utsname:sysname (uname)) "Windows"))

;;; ---------------------------------------------------------------------------
;;; Link creation
;;; ---------------------------------------------------------------------------

(define (create-link source target dry-run? overwrite? verbose?)
  "Create a symlink from TARGET -> SOURCE."
  (when verbose?
    (format #t "  link ~a -> ~a~%" target source))

  (cond
   (dry-run?
    (format #t "  [dry-run] would link: ~a -> ~a~%" target source))

   ((and (file-exists? target) (not overwrite?))
    (format (current-error-port)
            "  [skip] target exists: ~a (use --overwrite to replace)~%" target))

   (else
    (ensure-parent-dirs target)
    (when (file-exists? target)
      (delete-file target))
    (if (windows?)
        (create-link-windows source target verbose?)
        (symlink source target))
    (when verbose?
      (format #t "  [ok] linked ~a~%" target)))))

(define (ensure-parent-dirs path)
  "Recursively create parent directories of PATH."
  (let ((parent (dirname path)))
    (when (not (file-exists? parent))
      (ensure-parent-dirs parent)
      (mkdir parent))))

(define (create-link-windows source target verbose?)
  "Create an appropriate link on Windows (junction or symlink)."
  ;; Try mklink first (requires Developer Mode or admin)
  ;; Fall back to junction for directories, copy for files
  (let ((is-dir? (and (file-exists? source)
                      (eq? 'directory (stat:type (stat source))))))
    (if is-dir?
        ;; Directory junction (no admin needed)
        (system* "cmd" "/c" "mklink" "/J" target source)
        ;; File symlink (requires Developer Mode)
        (catch #t
          (lambda () (symlink source target))
          (lambda (key . args)
            (when verbose?
              (format #t "  [fallback] copying ~a (symlink unavailable)~%" source))
            (copy-file source target))))))

;;; ---------------------------------------------------------------------------
;;; Link removal
;;; ---------------------------------------------------------------------------

(define (remove-link target dry-run? verbose?)
  "Remove a managed symlink at TARGET."
  (cond
   (dry-run?
    (format #t "  [dry-run] would remove: ~a~%" target))
   ((not (file-exists? target))
    (when verbose?
      (format #t "  [skip] not found: ~a~%" target)))
   ((eq? 'symlink (stat:type (lstat target)))
    (delete-file target)
    (when verbose?
      (format #t "  [ok] removed ~a~%" target)))
   (else
    (format (current-error-port)
            "  [warn] ~a exists but is not a symlink — skipping~%" target))))

;;; ---------------------------------------------------------------------------
;;; Status
;;; ---------------------------------------------------------------------------

(define (link-status target source)
  "Return a symbol describing the state of TARGET.
   'ok       — symlink pointing to SOURCE
   'missing  — nothing at TARGET
   'wrong    — symlink pointing elsewhere
   'not-link — a real file/dir (not managed by ggstow)
   'broken   — dangling symlink"
  (cond
   ((not (file-exists? target))
    (if (and (file-exists? target) ; lstat would catch dangling symlinks
             (eq? 'symlink (stat:type (lstat target))))
        'broken
        'missing))
   ((not (eq? 'symlink (stat:type (lstat target))))
    'not-link)
   ((string=? (readlink target) source)
    'ok)
   (else 'wrong)))
