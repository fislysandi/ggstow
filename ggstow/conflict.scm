;;; ggstow/conflict.scm — Detect collisions before touching disk

(define-module (ggstow conflict)
  #:use-module (ggstow fs)
  #:export (detect-conflicts
            display-conflicts))

(define (detect-conflicts plan)
  "Return a list of (link . status) pairs where status is not 'ok or 'missing."
  (filter-map
   (lambda (link)
     (let ((status (link-status (link-target link) (link-source link))))
       (case status
         ((ok missing) #f)
         (else (cons link status)))))
   plan))

(define (display-conflicts conflicts)
  (display "ggstow: conflicts detected — use --overwrite to force:\n"
           (current-error-port))
  (for-each
   (lambda (pair)
     (let ((link   (car pair))
           (status (cdr pair)))
       (format (current-error-port) "  [~a] ~a~%"
               status (link-target link))))
   conflicts))
