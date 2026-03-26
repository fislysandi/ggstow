;;; ggstow/fs.scm — Filesystem abstraction layer
;;;
;;; Handles symlink creation, deletion, and status checks in a
;;; platform-aware way. On Windows: junctions for directories,
;;; symlinks where available, copies as fallback.

(define-module (ggstow fs)
  #:use-module (srfi srfi-13)   ; string-contains
  #:export (create-link
            remove-link
            link-status
            ensure-parent-dirs))

;;; ---------------------------------------------------------------------------
;;; Platform detection
;;; ---------------------------------------------------------------------------

(define (windows?)
  (let ((sysname (utsname:sysname (uname))))
    (or (string-contains sysname "MINGW")
        (string-contains sysname "CYGWIN"))))

;;; ---------------------------------------------------------------------------
;;; Parent directory creation
;;; ---------------------------------------------------------------------------

(define (ensure-parent-dirs path)
  "Recursively create parent directories of PATH if they don't exist."
  (let loop ((i (- (string-length path) 1)))
    (when (> i 0)
      (if (char=? (string-ref path i) #\/)
          (let ((parent (substring path 0 i)))
            (unless (or (string-null? parent) (file-exists? parent))
              (ensure-parent-dirs parent)
              (mkdir parent)))
          (loop (- i 1))))))

;;; ---------------------------------------------------------------------------
;;; Link creation
;;; ---------------------------------------------------------------------------

(define (create-link source target dry-run? overwrite? verbose?)
  "Create a symlink TARGET -> SOURCE."
  (cond
   (dry-run?
    (format #t "  [dry-run] ~a -> ~a~%" target source))

   ((and (file-exists? target) (not overwrite?))
    (format (current-error-port)
            "  [skip] target exists: ~a (use --overwrite to replace)~%" target))

   (else
    (ensure-parent-dirs target)
    (when (file-exists? target)
      (delete-file target))
    ;; Also handle dangling symlinks (lstat exists but stat doesn't)
    (catch #t
      (lambda ()
        (when (eq? 'symlink (stat:type (lstat target)))
          (delete-file target)))
      (lambda _ #f))
    (if (windows?)
        (create-link-windows source target verbose?)
        (begin
          (symlink source target)
          (when verbose?
            (format #t "  [ok] ~a~%" target)))))))

(define (create-link-windows source target verbose?)
  "Create an appropriate link on Windows: junction for dirs, symlink for files."
  (let ((is-dir? (and (file-exists? source)
                      (eq? 'directory (stat:type (stat source))))))
    (catch #t
      (lambda ()
        (if is-dir?
            (system* "cmd" "/c" "mklink" "/J" target source)
            (symlink source target))
        (when verbose?
          (format #t "  [ok] ~a~%" target)))
      (lambda (key . args)
        ;; Fallback: copy the file (Windows without Dev Mode)
        (when verbose?
          (format #t "  [copy-fallback] ~a~%" target))
        (copy-file source target)))))

;;; ---------------------------------------------------------------------------
;;; Link removal
;;; ---------------------------------------------------------------------------

(define (remove-link target dry-run? verbose?)
  "Remove a managed symlink at TARGET."
  (cond
   (dry-run?
    (format #t "  [dry-run] would remove: ~a~%" target))
   (else
    (catch #t
      (lambda ()
        (let ((type (stat:type (lstat target))))
          (if (eq? type 'symlink)
              (begin
                (delete-file target)
                (when verbose?
                  (format #t "  [removed] ~a~%" target)))
              (format (current-error-port)
                      "  [warn] ~a is not a symlink — skipping~%" target))))
      (lambda (key . args)
        (when verbose?
          (format #t "  [skip] not found: ~a~%" target)))))))

;;; ---------------------------------------------------------------------------
;;; Status
;;; ---------------------------------------------------------------------------

(define (link-status target source)
  "Return a symbol describing the state of TARGET relative to SOURCE.
   'ok       — symlink pointing to SOURCE
   'missing  — nothing at TARGET
   'broken   — dangling symlink (exists in lstat, not in stat)
   'wrong    — symlink pointing to a different source
   'not-link — a real file/dir (not managed by ggstow)"
  (catch #t
    (lambda ()
      (let ((lstat-result (lstat target)))
        (if (eq? 'symlink (stat:type lstat-result))
            ;; It's a symlink — check where it points
            (catch #t
              (lambda ()
                (stat target)  ; if this fails, it's dangling
                (if (string=? (readlink target) source)
                    'ok
                    'wrong))
              (lambda _ 'broken))
            ;; Not a symlink
            'not-link)))
    (lambda _ 'missing)))
