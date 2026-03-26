;;; ggstow/plan.scm — Compute the desired symlink graph
;;;
;;; Scans the Configs/ directory, resolves %VAR% path components,
;;; applies OS-suffix filtering, and produces a plan (list of link records).

(define-module (ggstow plan)
  #:use-module (srfi srfi-1)    ; append-map, any, fold, filter-map
  #:use-module (srfi srfi-9)    ; define-record-type
  #:use-module (srfi srfi-13)   ; string-suffix?, string-contains
  #:use-module (ice-9 rdelim)   ; read-line
  #:use-module (ggstow variables)
  #:export (compute-plan
            display-plan
            apply-plan
            rollback-plan
            display-status
            make-link link? link-source link-target link-package))

;;; ---------------------------------------------------------------------------
;;; Link record
;;; ---------------------------------------------------------------------------

(define-record-type <link>
  (make-link source target package)
  link?
  (source  link-source)    ; absolute path in the repo
  (target  link-target)    ; absolute path in $HOME
  (package link-package))  ; package name (top-level dir under Configs/)

;;; ---------------------------------------------------------------------------
;;; OS detection
;;; ---------------------------------------------------------------------------

(define (current-os)
  (let* ((sysname (utsname:sysname (uname))))
    (cond
     ((string-contains sysname "Linux")   'linux)
     ((string-contains sysname "Darwin")  'macos)
     ((string-contains sysname "MINGW")   'windows)
     ((string-contains sysname "CYGWIN")  'windows)
     (else 'unknown))))

(define (os-suffix os)
  (case os
    ((linux)   "_linux")
    ((macos)   "_macos")
    ((windows) "_windows")
    (else      "")))

;;; ---------------------------------------------------------------------------
;;; Directory listing (follows project patterns — opendir/readdir)
;;; ---------------------------------------------------------------------------

(define (list-dir path)
  "Return sorted list of entries in PATH, excluding . and .."
  (catch #t
    (lambda ()
      (let ((dir (opendir path)))
        (let loop ((acc '()))
          (let ((name (readdir dir)))
            (if (eof-object? name)
                (begin (closedir dir) (sort acc string<?))
                (if (member name '("." ".."))
                    (loop acc)
                    (loop (cons name acc))))))))
    (lambda (key . args)
      (format (current-error-port) "ggstow: cannot read directory: ~a~%" path)
      '())))

;;; ---------------------------------------------------------------------------
;;; Package filtering
;;; ---------------------------------------------------------------------------

(define *os-suffixes* '("_linux" "_macos" "_windows"))

(define (strip-os-suffix name)
  (fold (lambda (suffix acc)
          (if (string-suffix? suffix acc)
              (substring acc 0 (- (string-length acc) (string-length suffix)))
              acc))
        name *os-suffixes*))

(define (package-active? pkg-name os)
  "Return #t if PKG-NAME should be linked on OS."
  (let ((suffix (os-suffix os)))
    (if (any (lambda (s) (string-suffix? s pkg-name)) *os-suffixes*)
        ;; Has an explicit OS suffix — only match current OS
        (string-suffix? suffix pkg-name)
        ;; No suffix — active on all platforms
        #t)))

(define (read-ignore-file dir)
  "Return list of OS name strings from DIR/.ggstow-ignore, or '()."
  (let ((path (string-append dir "/.ggstow-ignore")))
    (if (file-exists? path)
        (call-with-input-file path
          (lambda (port)
            (let loop ((line (read-line port)) (acc '()))
              (if (eof-object? line)
                  acc
                  (let ((trimmed (string-trim-right line)))
                    (loop (read-line port)
                          (if (string-null? trimmed)
                              acc
                              (cons trimmed acc))))))))
        '())))

(define (package-ignored? pkg-dir os)
  "Return #t if current OS is listed in PKG-DIR/.ggstow-ignore."
  (member (symbol->string os) (read-ignore-file pkg-dir)))

;;; ---------------------------------------------------------------------------
;;; Config root resolution
;;; ---------------------------------------------------------------------------

(define (configs-dir config-path)
  "Resolve the Configs/ directory from the config file path (or cwd)."
  (let* ((base (if (string? config-path)
                   (let ((d (string-append
                             (substring config-path 0
                                        (let loop ((i (- (string-length config-path) 1)))
                                          (cond ((< i 0) 0)
                                                ((char=? (string-ref config-path i) #\/) i)
                                                (else (loop (- i 1)))))))))
                     (if (string=? d "") "." d))
                   (getcwd))))
    (string-append base "/Configs")))

;;; ---------------------------------------------------------------------------
;;; Plan computation
;;; ---------------------------------------------------------------------------

(define (compute-plan config)
  "Scan Configs/ and return a list of <link> records."
  (let* ((os      (current-os))
         (configs (configs-dir config))
         (home    (or (getenv "HOME") (error "ggstow: HOME not set"))))
    (unless (file-exists? configs)
      (error "ggstow: Configs/ directory not found" configs))
    (scan-packages configs home os)))

(define (scan-packages configs-dir home os)
  (let ((pkgs (list-dir configs-dir)))
    (append-map
     (lambda (pkg)
       (let ((pkg-dir (string-append configs-dir "/" pkg)))
         (if (and (eq? 'directory (stat:type (stat pkg-dir)))
                  (package-active? pkg os)
                  (not (package-ignored? pkg-dir os)))
             (scan-package pkg-dir home os (strip-os-suffix pkg))
             '())))
     pkgs)))

(define (scan-package pkg-dir home os pkg-name)
  "Walk PKG-DIR recursively, building link records."
  (let walk ((src-dir pkg-dir) (tgt-dir home))
    (append-map
     (lambda (entry)
       (cond
        ;; Always skip ignore file
        ((string=? entry ".ggstow-ignore") '())
        (else
         (let* ((src      (string-append src-dir "/" entry))
                (resolved (resolve-variable entry os))
                (tgt      (string-append tgt-dir "/" resolved))
                (type     (stat:type (stat src))))
           (cond
            ;; Directory (including %VAR% dirs) — recurse, don't link the dir itself
            ((eq? type 'directory)
             (walk src tgt))
            ;; Regular file or symlink — emit a link record
            (else
             (list (make-link src tgt pkg-name))))))))
     (list-dir src-dir))))

;;; ---------------------------------------------------------------------------
;;; Display
;;; ---------------------------------------------------------------------------

(define (display-plan plan verbose?)
  (if (null? plan)
      (display "ggstow: nothing to link.\n")
      (for-each
       (lambda (link)
         (format #t "  [~a] ~a\n        -> ~a\n"
                 (link-package link)
                 (link-target link)
                 (link-source link)))
       plan)))

(define (display-status plan verbose?)
  (use-modules (ggstow fs))
  (for-each
   (lambda (link)
     (let ((state (link-status (link-target link) (link-source link))))
       (format #t "  [~a] ~a\n" state (link-target link))))
   plan))

;;; ---------------------------------------------------------------------------
;;; Apply / rollback
;;; ---------------------------------------------------------------------------

(define (apply-plan plan dry-run? overwrite? verbose?)
  (use-modules (ggstow fs))
  (for-each
   (lambda (link)
     (create-link (link-source link) (link-target link)
                  dry-run? overwrite? verbose?))
   plan))

(define (rollback-plan plan dry-run? verbose?)
  (use-modules (ggstow fs))
  (for-each
   (lambda (link)
     (remove-link (link-target link) dry-run? verbose?))
   plan))
