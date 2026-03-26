;;; tests/plan.scm — Tests for (ggstow plan)
;;;
;;; Uses a synthetic fixture tree under /tmp/ggstow-test-fixtures/
;;; so tests never touch the real dotfiles.

(use-modules (srfi srfi-64)
             (srfi srfi-1)
             (ggstow plan))

;;; ---------------------------------------------------------------------------
;;; Fixture helpers
;;; ---------------------------------------------------------------------------

(define *fixture-root* "/tmp/ggstow-test-fixtures")
(define *fixture-configs* (string-append *fixture-root* "/Configs"))
(define *fixture-home*    (string-append *fixture-root* "/home"))

(define (make-fixture-file path)
  "Create an empty file at PATH, creating parent dirs as needed."
  (let loop ((i (- (string-length path) 1)))
    (when (> i 0)
      (if (char=? (string-ref path i) #\/)
          (let ((parent (substring path 0 i)))
            (unless (file-exists? parent)
              (loop i)
              (mkdir parent)))
          (loop (- i 1)))))
  (call-with-output-file path (lambda (p) (display "" p))))

(define (rmrf path)
  "Recursively delete PATH."
  (when (file-exists? path)
    (let ((type (stat:type (stat path))))
      (if (eq? type 'directory)
          (begin
            (for-each (lambda (f)
                        (rmrf (string-append path "/" f)))
                      (let ((d (opendir path)))
                        (let loop ((acc '()))
                          (let ((n (readdir d)))
                            (if (eof-object? n)
                                (begin (closedir d) acc)
                                (if (member n '("." ".."))
                                    (loop acc)
                                    (loop (cons n acc))))))))
            (rmdir path))
          (delete-file path)))))

(define (setup-fixtures!)
  "Create a clean fixture tree for testing."
  (rmrf *fixture-root*)
  (mkdir *fixture-root*)
  (mkdir *fixture-configs*)
  (mkdir *fixture-home*)

  ;; Package: git — plain files, no %VAR%, active everywhere
  (mkdir (string-append *fixture-configs* "/git"))
  (make-fixture-file (string-append *fixture-configs* "/git/.gitconfig"))

  ;; Package: nushell — has %NU_HOME% variable dir
  (let ((nu-pkg (string-append *fixture-configs* "/nushell")))
    (mkdir nu-pkg)
    (mkdir (string-append nu-pkg "/%NU_HOME%"))
    (make-fixture-file (string-append nu-pkg "/%NU_HOME%/config.nu"))
    (make-fixture-file (string-append nu-pkg "/%NU_HOME%/env.nu")))

  ;; Package: powershell_windows — OS-suffix filtered (Windows only)
  (let ((ps-pkg (string-append *fixture-configs* "/powershell_windows")))
    (mkdir ps-pkg)
    (make-fixture-file (string-append ps-pkg "/profile.ps1")))

  ;; Package: iterm2 — has .ggstow-ignore listing linux and windows
  (let ((iterm-pkg (string-append *fixture-configs* "/iterm2")))
    (mkdir iterm-pkg)
    (make-fixture-file (string-append iterm-pkg "/prefs.plist"))
    (call-with-output-file (string-append iterm-pkg "/.ggstow-ignore")
      (lambda (p)
        (display "linux\n" p)
        (display "windows\n" p)))))

(define (teardown-fixtures!)
  (rmrf *fixture-root*))

;;; ---------------------------------------------------------------------------
;;; scan helpers — run compute-plan against fixture tree
;;; ---------------------------------------------------------------------------

(define (fixture-plan)
  ;; Override HOME so %NU_HOME% resolves under our fixture home
  (let ((orig-home (getenv "HOME"))
        (orig-xdg  (getenv "XDG_CONFIG_HOME")))
    (setenv "HOME" *fixture-home*)
    (setenv "XDG_CONFIG_HOME" (string-append *fixture-home* "/.config"))
    (let ((plan (compute-plan (string-append *fixture-root* "/.ggstow.scm"))))
      (when orig-home (setenv "HOME" orig-home))
      (when orig-xdg  (setenv "XDG_CONFIG_HOME" orig-xdg))
      (unless orig-home (unsetenv "HOME"))
      (unless orig-xdg  (unsetenv "XDG_CONFIG_HOME"))
      plan)))

;;; ---------------------------------------------------------------------------
;;; Tests
;;; ---------------------------------------------------------------------------

(test-begin "plan")

(setup-fixtures!)

(test-group "compute-plan — basic"
  (let ((plan (fixture-plan)))

    (test-assert "returns a list"
      (list? plan))

    (test-assert "plan is non-empty"
      (not (null? plan)))

    (test-assert "all entries are link records"
      (every link? plan))))

(test-group "compute-plan — git package"
  (let* ((plan  (fixture-plan))
         (links (filter (lambda (l) (string=? (link-package l) "git")) plan)))

    (test-assert ".gitconfig is in plan"
      (any (lambda (l) (string-suffix? "/.gitconfig" (link-target l)))
           links))

    (test-assert ".gitconfig source points into fixture Configs/"
      (any (lambda (l) (string-contains (link-source l) "Configs/git"))
           links))))

(test-group "compute-plan — %NU_HOME% variable expansion"
  (let* ((plan  (fixture-plan))
         (links (filter (lambda (l) (string=? (link-package l) "nushell")) plan)))

    (test-assert "nushell package produces links"
      (not (null? links)))

    (test-assert "config.nu target is under ~/.config/nushell"
      (any (lambda (l) (and (string-suffix? "/config.nu" (link-target l))
                            (string-contains (link-target l) "nushell")))
           links))

    (test-assert "env.nu is also linked"
      (any (lambda (l) (string-suffix? "/env.nu" (link-target l)))
           links))

    (test-assert "no target contains literal %NU_HOME%"
      (not (any (lambda (l) (string-contains (link-target l) "%NU_HOME%"))
                links)))))

(test-group "compute-plan — OS-suffix filtering"
  (let ((plan (fixture-plan)))

    (test-assert "powershell_windows not in plan on Linux"
      (not (any (lambda (l) (string=? (link-package l) "powershell"))
                plan)))))

(test-group "compute-plan — .ggstow-ignore"
  (let ((plan (fixture-plan)))

    (test-assert "iterm2 excluded on Linux via .ggstow-ignore"
      (not (any (lambda (l) (string=? (link-package l) "iterm2"))
                plan)))))

(test-group "compute-plan — no .ggstow-ignore files appear as links"
  (let ((plan (fixture-plan)))
    (test-assert "no link source is .ggstow-ignore"
      (not (any (lambda (l) (string-suffix? "/.ggstow-ignore" (link-source l)))
                plan)))))

(teardown-fixtures!)

(test-end "plan")
