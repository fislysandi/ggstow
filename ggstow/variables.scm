;;; ggstow/variables.scm — %VARIABLE% directory name resolution
;;;
;;; Maps %VAR% tokens in directory names to OS-specific paths.
;;; Replaces nutuck's Applications/*.nu plugin system with a declarative
;;; Scheme alist. Additional mappings can be declared in .ggstow.scm.

(define-module (ggstow variables)
  #:use-module (ice-9 regex)
  #:export (variable-dir?
            resolve-variable
            register-variable!
            default-variables))

;;; ---------------------------------------------------------------------------
;;; Built-in variable table
;;; ---------------------------------------------------------------------------

(define *variable-table* '())

(define (register-variable! name resolver)
  "Register a variable NAME with a RESOLVER thunk (no args → string)."
  (set! *variable-table*
        (cons (cons name resolver) *variable-table*)))

(define (lookup-variable name)
  (let ((entry (assoc name *variable-table*)))
    (and entry ((cdr entry)))))

;;; ---------------------------------------------------------------------------
;;; Predicate
;;; ---------------------------------------------------------------------------

(define *var-rx* (make-regexp "^%[A-Z0-9_]+%$"))

(define (variable-dir? name)
  "Return #t if NAME is a %VARIABLE% style token."
  (regexp-exec *var-rx* name))

;;; ---------------------------------------------------------------------------
;;; Resolution
;;; ---------------------------------------------------------------------------

(define (resolve-variable token os)
  "Resolve TOKEN (may contain %VAR%) to a concrete path segment."
  (let ((match (regexp-exec (make-regexp "%([A-Z0-9_]+)%") token)))
    (if match
        (let* ((var-name (match:substring match 1))
               (resolved (or (lookup-variable var-name)
                             (getenv var-name)
                             (default-variable var-name os))))
          (if resolved
              resolved
              (begin
                (format (current-error-port)
                        "ggstow: warning: unresolved variable %~a%~%" var-name)
                token)))
        token)))

;;; ---------------------------------------------------------------------------
;;; Default variable definitions
;;; ---------------------------------------------------------------------------

(define (home) (getenv "HOME"))
(define (appdata) (or (getenv "APPDATA") (string-append (home) "/AppData/Roaming")))
(define (localappdata) (or (getenv "LOCALAPPDATA") (string-append (home) "/AppData/Local")))
(define (xdg-config) (or (getenv "XDG_CONFIG_HOME") (string-append (home) "/.config")))

(define (default-variable var os)
  "Return a path for VAR on OS, or #f if unknown."
  (case (string->symbol var)

    ;; --- Nushell ---
    ((NU_HOME)
     (case os
       ((windows) (string-append appdata "/nushell"))
       (else      (string-append (xdg-config) "/nushell"))))

    ;; --- Neovim ---
    ((NVIM_CONFIG)
     (case os
       ((windows) (string-append localappdata "/nvim"))
       (else      (string-append (xdg-config) "/nvim"))))

    ;; --- VS Code ---
    ((CODE_USER)
     (case os
       ((linux)   (string-append (xdg-config) "/Code/User"))
       ((macos)   (string-append (home) "/Library/Application Support/Code/User"))
       ((windows) (string-append appdata "/Code/User"))
       (else      (string-append (xdg-config) "/Code/User"))))

    ;; --- MPV ---
    ((MPV_HOME)
     (case os
       ((windows) (string-append appdata "/mpv"))
       (else      (string-append (xdg-config) "/mpv"))))

    ;; --- Blender ---
    ((BLENDER_CONFIG)
     (case os
       ((linux)   (string-append (xdg-config) "/blender"))
       ((macos)   (string-append (home) "/Library/Application Support/Blender"))
       ((windows) (string-append appdata "/Blender Foundation/Blender"))
       (else      (string-append (xdg-config) "/blender"))))

    ;; --- Yazi ---
    ((YAZI_CONFIG)
     (case os
       ((windows) (string-append appdata "/yazi/config"))
       (else      (string-append (xdg-config) "/yazi"))))

    ;; --- Nyxt ---
    ((NYXT_HOME)
     (case os
       ((windows) (string-append appdata "/nyxt"))
       (else
        ;; Prefer Flatpak path if present
        (let ((flatpak (string-append (home) "/.var/app/engineer.atlas.Nyxt/config/nyxt")))
          (if (file-exists? (string-append (home) "/.var/app/engineer.atlas.Nyxt"))
              flatpak
              (string-append (xdg-config) "/nyxt"))))))

    ;; --- Windows Terminal ---
    ((WT_CONFIG_DIR)
     (string-append localappdata "/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState"))

    ;; --- PowerShell ---
    ((PS_PROFILE_DIR)
     (case os
       ((windows) (string-append (home) "/Documents/PowerShell"))
       (else      (string-append (xdg-config) "/powershell"))))

    ;; --- Guix ---
    ((GUIX_CONFIG)
     (string-append (xdg-config) "/guix"))

    (else #f)))

(define (default-variables)
  "Return the list of all registered variable names."
  (map car *variable-table*))
