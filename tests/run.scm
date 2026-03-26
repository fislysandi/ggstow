#!/usr/bin/env -S guile --no-auto-compile -s
!#

;;; tests/run.scm — Test runner entry point
;;;
;;; Usage:
;;;   guile tests/run.scm
;;;   guile tests/run.scm --verbose

(eval-when (expand load eval)
  (let* ((here (or (current-filename) (car (command-line)) "."))
         ;; Strip filename → tests/ dir, then strip tests/ → repo root
         (strip-last (lambda (path)
                       (let loop ((i (- (string-length path) 1)))
                         (cond ((< i 0) ".")
                               ((char=? (string-ref path i) #\/) (substring path 0 i))
                               (else (loop (- i 1)))))))
         (root (strip-last (strip-last here))))
    (unless (member root %load-path)
      (set! %load-path (cons root %load-path)))))

(use-modules (srfi srfi-64))

;; Load all test modules (relative to this file's directory)
(load "variables.scm")
(load "plan.scm")
(load "fs.scm")
