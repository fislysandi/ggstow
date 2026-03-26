;;; tests/fs.scm — Tests for (ggstow fs)

(use-modules (srfi srfi-64)
             (ggstow fs))

(define *tmp* "/tmp/ggstow-fs-test")

(define (setup!)
  (when (file-exists? *tmp*) (rmrf *tmp*))
  (mkdir *tmp*)
  (mkdir (string-append *tmp* "/src"))
  (mkdir (string-append *tmp* "/dst")))

(define (rmrf path)
  (when (file-exists? path)
    (let ((type (catch #t
                  (lambda () (stat:type (lstat path)))
                  (lambda _ 'unknown))))
      (cond
       ((eq? type 'symlink) (delete-file path))
       ((eq? type 'directory)
        (let ((d (opendir path)))
          (let loop ()
            (let ((n (readdir d)))
              (unless (eof-object? n)
                (unless (member n '("." ".."))
                  (rmrf (string-append path "/" n)))
                (loop))))
          (closedir d))
        (rmdir path))
       (else (delete-file path))))))

(define (touch! path)
  (call-with-output-file path (lambda (p) (display "test\n" p))))

(define (teardown!)
  (rmrf *tmp*))

;;; ---------------------------------------------------------------------------
;;; Tests
;;; ---------------------------------------------------------------------------

(test-begin "fs")

(test-group "ensure-parent-dirs"
  (setup!)
  (let ((deep (string-append *tmp* "/dst/a/b/c/file.txt")))
    (ensure-parent-dirs deep)
    (test-assert "parent dirs created"
      (file-exists? (string-append *tmp* "/dst/a/b/c")))
    (test-assert "file itself not created"
      (not (file-exists? deep))))
  (teardown!))

(test-group "create-link — happy path"
  (setup!)
  (let ((src (string-append *tmp* "/src/file.txt"))
        (tgt (string-append *tmp* "/dst/file.txt")))
    (touch! src)
    (create-link src tgt #f #f #f)
    (test-assert "symlink created"
      (eq? 'symlink (stat:type (lstat tgt))))
    (test-equal "symlink points to source"
      src (readlink tgt)))
  (teardown!))

(test-group "create-link — dry-run"
  (setup!)
  (let ((src (string-append *tmp* "/src/file.txt"))
        (tgt (string-append *tmp* "/dst/file.txt")))
    (touch! src)
    (create-link src tgt #t #f #f)
    (test-assert "symlink NOT created in dry-run"
      (not (file-exists? tgt))))
  (teardown!))

(test-group "create-link — skip existing without overwrite"
  (setup!)
  (let ((src  (string-append *tmp* "/src/file.txt"))
        (tgt  (string-append *tmp* "/dst/file.txt"))
        (src2 (string-append *tmp* "/src/other.txt")))
    (touch! src)
    (touch! src2)
    ;; Create a real file at target (not managed by ggstow)
    (touch! tgt)
    (create-link src tgt #f #f #f)
    ;; Target should still be the real file, not a symlink
    (test-assert "existing file not replaced without --overwrite"
      (not (eq? 'symlink (stat:type (lstat tgt))))))
  (teardown!))

(test-group "create-link — overwrite existing"
  (setup!)
  (let ((src (string-append *tmp* "/src/file.txt"))
        (tgt (string-append *tmp* "/dst/file.txt")))
    (touch! src)
    (touch! tgt)
    (create-link src tgt #f #t #f)
    (test-assert "existing file replaced with symlink"
      (eq? 'symlink (stat:type (lstat tgt))))
    (test-equal "symlink points to source"
      src (readlink tgt)))
  (teardown!))

(test-group "create-link — creates parent dirs"
  (setup!)
  (let ((src (string-append *tmp* "/src/file.txt"))
        (tgt (string-append *tmp* "/dst/a/b/file.txt")))
    (touch! src)
    (create-link src tgt #f #f #f)
    (test-assert "parent dirs auto-created"
      (file-exists? (string-append *tmp* "/dst/a/b")))
    (test-assert "symlink created in nested dir"
      (eq? 'symlink (stat:type (lstat tgt)))))
  (teardown!))

(test-group "remove-link"
  (setup!)
  (let ((src (string-append *tmp* "/src/file.txt"))
        (tgt (string-append *tmp* "/dst/file.txt")))
    (touch! src)
    (symlink src tgt)
    (remove-link tgt #f #f)
    (test-assert "symlink removed"
      (not (file-exists? tgt))))
  (teardown!))

(test-group "remove-link — dry-run"
  (setup!)
  (let ((src (string-append *tmp* "/src/file.txt"))
        (tgt (string-append *tmp* "/dst/file.txt")))
    (touch! src)
    (symlink src tgt)
    (remove-link tgt #t #f)
    (test-assert "symlink NOT removed in dry-run"
      (eq? 'symlink (stat:type (lstat tgt)))))
  (teardown!))

(test-group "remove-link — skips non-symlinks"
  (setup!)
  (let ((tgt (string-append *tmp* "/dst/real-file.txt")))
    (touch! tgt)
    ;; Should not throw or delete the real file
    (remove-link tgt #f #f)
    (test-assert "real file not deleted"
      (file-exists? tgt)))
  (teardown!))

(test-group "link-status"
  (setup!)
  (let ((src     (string-append *tmp* "/src/file.txt"))
        (tgt     (string-append *tmp* "/dst/file.txt"))
        (tgt2    (string-append *tmp* "/dst/other.txt"))
        (tgt3    (string-append *tmp* "/dst/real.txt"))
        (missing (string-append *tmp* "/dst/nowhere.txt")))
    (touch! src)
    ;; OK: symlink → src
    (symlink src tgt)
    (test-equal "ok when symlink points to source"
      'ok (link-status tgt src))

    ;; Wrong: symlink → different file
    (touch! (string-append *tmp* "/src/wrong.txt"))
    (symlink (string-append *tmp* "/src/wrong.txt") tgt2)
    (test-equal "wrong when symlink points elsewhere"
      'wrong (link-status tgt2 src))

    ;; Not-link: real file
    (touch! tgt3)
    (test-equal "not-link for real file"
      'not-link (link-status tgt3 src))

    ;; Missing: nothing there
    (test-equal "missing when no file exists"
      'missing (link-status missing src)))
  (teardown!))

(test-end "fs")
