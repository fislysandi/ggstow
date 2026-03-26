;;; tests/variables.scm — Tests for (ggstow variables)

(use-modules (srfi srfi-64)
             (ggstow variables))

(test-begin "variables")

;;; ---------------------------------------------------------------------------
;;; variable-dir?
;;; ---------------------------------------------------------------------------

(test-group "variable-dir?"
  (test-assert "detects %NU_HOME%"
    (variable-dir? "%NU_HOME%"))

  (test-assert "detects %CODE_USER%"
    (variable-dir? "%CODE_USER%"))

  (test-assert "detects single token %X%"
    (variable-dir? "%X%"))

  (test-assert "rejects plain directory name"
    (not (variable-dir? "nushell")))

  (test-assert "rejects partial token"
    (not (variable-dir? "%NUSHELL")))

  (test-assert "rejects lowercase"
    (not (variable-dir? "%nu_home%"))))

;;; ---------------------------------------------------------------------------
;;; resolve-variable — no substitution
;;; ---------------------------------------------------------------------------

(test-group "resolve-variable — plain names"
  (test-equal "plain name returned unchanged"
    "config.nu"
    (resolve-variable "config.nu" 'linux))

  (test-equal "dotfile returned unchanged"
    ".gitconfig"
    (resolve-variable ".gitconfig" 'linux)))

;;; ---------------------------------------------------------------------------
;;; resolve-variable — known variables on Linux
;;; ---------------------------------------------------------------------------

(test-group "resolve-variable — Linux paths"
  (let ((home (getenv "HOME")))

    (test-equal "%NU_HOME% → ~/.config/nushell"
      (string-append home "/.config/nushell")
      (resolve-variable "%NU_HOME%" 'linux))

    (test-equal "%NVIM_CONFIG% → ~/.config/nvim"
      (string-append home "/.config/nvim")
      (resolve-variable "%NVIM_CONFIG%" 'linux))

    (test-equal "%MPV_HOME% → ~/.config/mpv"
      (string-append home "/.config/mpv")
      (resolve-variable "%MPV_HOME%" 'linux))

    (test-equal "%YAZI_CONFIG% → ~/.config/yazi"
      (string-append home "/.config/yazi")
      (resolve-variable "%YAZI_CONFIG%" 'linux))

    (test-equal "%GUIX_CONFIG% → ~/.config/guix"
      (string-append home "/.config/guix")
      (resolve-variable "%GUIX_CONFIG%" 'linux))))

;;; ---------------------------------------------------------------------------
;;; resolve-variable — macOS paths differ where expected
;;; ---------------------------------------------------------------------------

(test-group "resolve-variable — macOS paths"
  (let ((home (getenv "HOME")))

    (test-equal "%CODE_USER% on macOS → Application Support"
      (string-append home "/Library/Application Support/Code/User")
      (resolve-variable "%CODE_USER%" 'macos))

    (test-equal "%BLENDER_CONFIG% on macOS → Application Support"
      (string-append home "/Library/Application Support/Blender")
      (resolve-variable "%BLENDER_CONFIG%" 'macos))))

;;; ---------------------------------------------------------------------------
;;; resolve-variable — env var override
;;; ---------------------------------------------------------------------------

(test-group "resolve-variable — env var fallback"
  (let ((orig (getenv "XDG_CONFIG_HOME")))
    ;; Set a custom XDG_CONFIG_HOME
    (setenv "XDG_CONFIG_HOME" "/tmp/test-config")
    (test-equal "%NU_HOME% respects XDG_CONFIG_HOME"
      "/tmp/test-config/nushell"
      (resolve-variable "%NU_HOME%" 'linux))
    ;; Restore
    (if orig
        (setenv "XDG_CONFIG_HOME" orig)
        (unsetenv "XDG_CONFIG_HOME"))))

;;; ---------------------------------------------------------------------------
;;; register-variable!
;;; ---------------------------------------------------------------------------

(test-group "register-variable!"
  (register-variable! "MY_TOOL"
                      (lambda () "/opt/my-tool/config"))

  (test-equal "registered variable resolves"
    "/opt/my-tool/config"
    (resolve-variable "%MY_TOOL%" 'linux)))

(test-end "variables")
