;;; ggstow/plan.scm — Compute the desired symlink graph
;;;
;;; Scans the Configs/ directory, resolves %VAR% path components,
;;; applies OS-suffix filtering, and produces a plan (list of link records).

(define-module (ggstow plan)
  #:use-module (ggstow variables)
  #:use-module (ggstow fs)
  #:use-module (ice-9 ftw)
  #:use-module (ice-9 regex)
  #:use-module (ice-9 string-fun)
  #:use-module (srfi srfi-1)
  #:export (compute-plan
            display-plan
            apply-plan
            rollback-plan
            display-status))

;;; ---------------------------------------------------------------------------
;;; Link record
;;; ---------------------------------------------------------------------------

(define-record-type <link>
  (make-link source target package)
  link?
  (source  link-source)   ; absolute path in the repo
  (target  link-target)   ; absolute path in $HOME
  (package link-package)) ; package name (top-level dir under Configs/)

;;; ---------------------------------------------------------------------------
;;; OS detection
;;; ---------------------------------------------------------------------------

(define (current-os)
  (let ((uname (uname)))
    (cond
     ((string-contains (utsname:sysname uname) "Linux")   'linux)
     ((string-contains (utsname:sysname uname) "Darwin")  'macos)
     ((string-contains (utsname:sysname uname) "Windows") 'windows)
     (else 'unknown))))

(define (os-suffix os)
  (case os
    ((linux)   "_linux")
    ((macos)   "_macos")
    ((windows) "_windows")
    (else      "")))

;;; ---------------------------------------------------------------------------
;;; Package filtering
;;; ---------------------------------------------------------------------------

(define *os-suffixes* '("_linux" "_macos" "_windows"))

(define (package-active? pkg-name os)
  "Return #t if PKG-NAME should be linked on OS."
  (let ((suffix (os-suffix os)))
    (cond
     ;; Explicit OS suffix — only link if it matches
     ((any (lambda (s) (string-suffix? s pkg-name)) *os-suffixes*)
      (string-suffix? suffix pkg-name))
     ;; No suffix — link on all platforms
     (else #t))))

(define (read-ignore-file dir)
  "Return list of OS names to exclude from DIR/.ggstow-ignore, or '()."
  (let ((ignore-path (string-append dir "/.ggstow-ignore")))
    (if (file-exists? ignore-path)
        (call-with-input-file ignore-path
          (lambda (port)
            (let loop ((line (read-line port)) (acc '()))
              (if (eof-object? line)
                  acc
                  (loop (read-line port)
                        (cons (string-trim-right line) acc))))))
        '())))

(define (package-ignored? pkg-dir os)
  "Return #t if OS is listed in PKG-DIR/.ggstow-ignore."
  (let ((excluded (read-ignore-file pkg-dir))
        (os-name  (symbol->string os)))
    (member os-name excluded)))

;;; ---------------------------------------------------------------------------
;;; Plan computation
;;; ---------------------------------------------------------------------------

(define (configs-dir config)
  "Resolve the Configs/ directory from the config file location."
  (let ((base (dirname (if (string? config) config (getcwd)))))
    (string-append base "/Configs")))

(define (compute-plan config)
  "Scan Configs/ and return a list of <link> records."
  (let* ((os      (current-os))
         (configs (configs-dir config))
         (home    (getenv "HOME")))
    (if (not (file-exists? configs))
        (error "ggstow: Configs/ directory not found" configs)
        (scan-packages configs home os))))

(define (scan-packages configs-dir home os)
  (let ((packages (scandir configs-dir
                           (lambda (f)
                             (and (not (string=? f "."))
                                  (not (string=? f ".."))
                                  (eq? 'directory
                                       (stat:type (stat (string-append configs-dir "/" f)))))))))
    (append-map
     (lambda (pkg)
       (let* ((pkg-dir    (string-append configs-dir "/" pkg))
              (pkg-name   (strip-os-suffix pkg)))
         (if (or (not (package-active? pkg os))
                 (package-ignored? pkg-dir os))
             '()
             (scan-package pkg-dir home os pkg-name))))
     (or packages '()))))

(define (strip-os-suffix name)
  (fold (lambda (suffix acc)
          (if (string-suffix? suffix acc)
              (substring acc 0 (- (string-length acc) (string-length suffix)))
              acc))
        name *os-suffixes*))

(define (scan-package pkg-dir home os pkg-name)
  "Walk PKG-DIR, resolving %VAR% dirs, and produce link records."
  (let loop ((dir    pkg-dir)
             (target home)
             (links  '()))
    (let ((entries (scandir dir (lambda (f)
                                  (and (not (string=? f "."))
                                       (not (string=? f ".."))
                                       (not (string=? f ".ggstow-ignore")))))))
      (fold
       (lambda (entry acc)
         (let* ((src      (string-append dir "/" entry))
                (resolved (resolve-variable entry os))
                (tgt      (string-append target "/" resolved))
                (type     (stat:type (stat src))))
           (cond
            ;; %VAR% directory — recurse into it
            ((and (eq? type 'directory) (variable-dir? entry))
             (loop src tgt acc))
            ;; Regular directory — recurse
            ((eq? type 'directory)
             (loop src tgt acc))
            ;; File — emit a link record
            (else
             (cons (make-link src tgt pkg-name) acc)))))
       links
       (or entries '())))))

;;; ---------------------------------------------------------------------------
;;; Display
;;; ---------------------------------------------------------------------------

(define (display-plan plan verbose?)
  (if (null? plan)
      (display "ggstow: nothing to link.\n")
      (for-each
       (lambda (link)
         (format #t "  ~a\n    -> ~a\n"
                 (link-target link)
                 (link-source link)))
       plan)))

(define (display-status plan verbose?)
  (for-each
   (lambda (link)
     (let* ((tgt    (link-target link))
            (state  (cond
                     ((not (file-exists? tgt))     "MISSING")
                     ((not (eq? 'symlink (stat:type (lstat tgt)))) "NOT-LINK")
                     ((string=? (readlink tgt) (link-source link))  "OK")
                     (else "MISMATCH"))))
       (format #t "  [~a] ~a\n" state tgt)))
   plan))

;;; ---------------------------------------------------------------------------
;;; Apply / rollback
;;; ---------------------------------------------------------------------------

(define (apply-plan plan dry-run? overwrite? verbose?)
  (for-each
   (lambda (link)
     (create-link (link-source link) (link-target link) dry-run? overwrite? verbose?))
   plan))

(define (rollback-plan plan dry-run? verbose?)
  (for-each
   (lambda (link)
     (remove-link (link-target link) dry-run? verbose?))
   plan))
