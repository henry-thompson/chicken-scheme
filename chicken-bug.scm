;;;; chicken-bug.scm - Bug report-generator


(use posix utils)


#>
#ifndef C_TARGET_CC
# define C_TARGET_CC  C_INSTALL_CC
#endif

#ifndef C_TARGET_CXX
# define C_TARGET_CXX  C_INSTALL_CXX
#endif
<#


(define-constant +bug-report-file+ "chicken-bug-report.~a-~a-~a")

(define-constant +destinations+ 
  "chicken-janitors@nongnu.org\nchicken-hackers@nongnu.org\nchicken-users@nongnu.org\nfelix@call-with-current-continuation.org")


(define-foreign-variable +cc+ c-string "C_TARGET_CC")
(define-foreign-variable +cxx+ c-string "C_TARGET_CXX")
(define-foreign-variable +c-include-path+ c-string "C_INSTALL_INCLUDE_HOME")


(define (collect-info)
  (print "\n--------------------------------------------------\n")
  (print "This is a bug report generated by chicken-bug(1).\n")
  (print "Date:\t" (seconds->string (current-seconds)) "\n")
  (printf "User information:\t~s~%~%" (user-information (current-user-id)))
  (print "Host information:\n")
  (print "\tmachine type:\t" (machine-type))
  (print "\tsoftware type:\t" (software-type))
  (print "\tsoftware version:\t" (software-version))
  (print "\tbuild platform:\t" (build-platform) "\n")
  (print "CHICKEN version is:\n" (chicken-version #t) "\n")
  (print "Home directory:\t" (chicken-home) "\n")
  (printf "Include path:\t~s~%~%" ##sys#include-pathnames)
  (print "Features:")
  (for-each
   (lambda (lst) 
     (display "\n  ")
     (for-each 
      (lambda (f)
	(printf "~a~a" f (make-string (fxmax 1 (fx- 16 (string-length f))) #\space)) )
      lst) )
   (chop (sort (map keyword->string ##sys#features) string<?) 5))
  (print "\n\nchicken-config.h:\n")
  (with-input-from-file (make-pathname +c-include-path+ "chicken-config.h")
    (lambda ()
      (display (read-all)) ) )
  (newline)
  (when (and (string=? +cc+ "gcc") (feature? 'unix))
    (print "CC seems to be gcc, trying to obtain version...\n")
    (with-input-from-pipe "gcc -v 2>&1"
      (lambda ()
	(display (read-all)))))
  (newline) )

(define (usage code)
  (print #<<EOF
usage: chicken-bug [FILENAME ...]

  -help  -h            show this message
  -to-stdout           write bug report to standard output
  -                    read description from standard input

Generates a bug report file from user input or alternatively
from the contents of files given on the command line.

EOF
) 
  (exit code) )

(define (user-input)
  (when (##sys#tty-port? (current-input-port))
    (print #<<EOF
This is the CHICKEN bug report generator. Please enter a detailed
description of the problem you have encountered and enter CTRL-D (EOF)
once you have finished. Press CTRL-C to abort the program. You can
also pass the description from a file (just abort now and re-invoke
"chicken-bug" with one or more input files given on the command-line)

EOF
) )
  (read-all) )

(define (justify n)
  (let ((s (number->string n)))
    (if (> (string-length s) 1)
	s
	(string-append "0" s))))

(define (main args)
  (let ((msg "")
	(files #f)
	(stdout #f))
    (for-each
     (lambda (arg)
       (cond ((string=? "-" arg) 
	      (set! files #t)
	      (set! msg (string-append msg "\n\nUser input:\n\n" (user-input))) )
	     ((member arg '("--help" "-h" "-help"))
	      (usage 0) )
	     ((string=? "-to-stdout" arg)
	      (set! stdout #t) )
	     (else
	      (set! files #t)
	      (set! msg 
		(string-append
		 msg
		 "\n\nFile added: " arg "\n\n"
		 (read-all arg) ) ) ) ) )
     args)
    (unless files
      (set! msg (string-append msg "\n\n" (user-input))))
    (match-let ((#(_ _ _ day mon yr _ _ _ _) (seconds->local-time (current-seconds))))
      (let* ((file (sprintf +bug-report-file+ (+ 1900 yr) (justify mon) (justify day)))
	     (port (if stdout (current-output-port) (open-output-file file))))
	(with-output-to-port port
	  (lambda ()
	    (print msg)
	    (collect-info) ) )
	(unless stdout
	  (close-output-port port)
	  (print "\nA bug report has been written to `" file "'. Please send it to")
	  (print "one of the following addresses:\n\n" +destinations+) ) ) ) ) )

(main (command-line-arguments))
