;;;; regex.scm - Unit for using the PCRE regex package
;
; Copyright (c) 2000-2007, Felix L. Winkelmann
; All rights reserved.
;
; Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following
; conditions are met:
;
;   Redistributions of source code must retain the above copyright notice, this list of conditions and the following
;     disclaimer.
;   Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following
;     disclaimer in the documentation and/or other materials provided with the distribution.
;   Neither the name of the author nor the names of its contributors may be used to endorse or promote
;     products derived from this software without specific prior written permission.
;
; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS
; OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
; AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS OR
; CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
; CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
; SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
; THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
; OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
; POSSIBILITY OF SUCH DAMAGE.
;
; Send bugs, suggestions and ideas to:
;
; felix@call-with-current-continuation.org
;
; Felix L. Winkelmann
; Unter den Gleichen 1
; 37130 Gleichen
; Germany


(cond-expand
 [chicken-compile-shared]
 [else (declare (unit regex))] )

(declare
  (usual-integrations)
  (disable-interrupts)
  (generic) ; PCRE options use lotsa bits
  (disable-warning var)
  (export
    pcre-version
    regexp? regexp regexp*
    regexp-optimization-set! regexp-optimize regexp-extra-info
    regex-chardef-table? regex-chardef-table
    regex-chardef-set! regex-chardefs-update! regex-chardefs
    set-regexp-options! regexp-options
    regexp-info regexp-info-nametable
    pcre-config-info
    make-anchored-pattern
    string-match string-match-positions string-search string-search-positions
    string-split-fields string-substitute string-substitute*
    glob? glob->regexp
    grep
    regexp-escape)
  (bound-to-procedure
    ;; Forward reference
    check-chardef-table make-anchored-pattern
    ;; Imports
    get-output-string open-output-string
    string->list list->string string-length string-ref substring make-string string-append
    reverse list-ref
    char=? char-alphabetic? char-numeric?
    set-finalizer!
    ##sys#make-tagged-pointer
    ##sys#slot ##sys#setslot ##sys#size
    ##sys#make-structure ##sys#structure?
    ##sys#error ##sys#signal-hook
    ##sys#substring ##sys#fragments->string ##sys#make-c-string ##sys#string-append
    ##sys#write-char-0) )

(cond-expand
 [paranoia]
 [else
  (declare
    (no-bound-checks)
    (no-procedure-checks-for-usual-bindings)
    ) ] )

(cond-expand
 [unsafe
  (eval-when (compile)
    (define-macro (##sys#check-integer . _) '(##core#undefined))
    (define-macro (##sys#check-blob . _) '(##core#undefined))
    (define-macro (##sys#check-vector . _) '(##core#undefined))
    (define-macro (##sys#check-structure . _) '(##core#undefined))
    (define-macro (##sys#check-range . _) '(##core#undefined))
    (define-macro (##sys#check-pair . _) '(##core#undefined))
    (define-macro (##sys#check-list . _) '(##core#undefined))
    (define-macro (##sys#check-symbol . _) '(##core#undefined))
    (define-macro (##sys#check-string . _) '(##core#undefined))
    (define-macro (##sys#check-char . _) '(##core#undefined))
    (define-macro (##sys#check-exact . _) '(##core#undefined))
    (define-macro (##sys#check-port . _) '(##core#undefined))
    (define-macro (##sys#check-number . _) '(##core#undefined))
    (define-macro (##sys#check-byte-vector . _) '(##core#undefined)) ) ]
 [else
  (declare
    (bound-to-procedure
      ;; Imports
      ##sys#check-string ##sys#check-list ##sys#check-exact ##sys#check-vector
      ##sys#check-structure ##sys#check-symbol ##sys#check-blob ##sys#check-integer)
    (emit-exports "regex.exports")) ] )


;;;

;FIXME should have a common handler in "runtime.c"
(foreign-declare #<<EOF
static void
out_of_memory_failure(const char *modnam, const char *prcnam, const char *typnam)
{
  fprintf(stderr, "%s@%s: out of memory - cannot allocate %s", modnam, prcnam, typnam);
  exit(EXIT_FAILURE);
}
EOF
)

(foreign-declare "#include \"pcre/pcre.h\"")


;;;

(register-feature! 'regex 'pcre)


;;; From unit lolevel:

(define-inline (%tag-pointer ptr tag)
  (let ([tp (##sys#make-tagged-pointer tag)])
    (##core#inline "C_copy_pointer" ptr tp)
    tp) )

(define-inline (%tagged-pointer? x tag)
  (and (##core#inline "C_blockp" x)
       (##core#inline "C_taggedpointerp" x)
       (equal? tag (##sys#slot x 1)) ) )


;;; Which version of PCRE:

(define pcre-version
  (let ([substring substring]
        [substring-index substring-index])
    (lambda ()
      (let ([str ((foreign-lambda nonnull-c-string "pcre_version"))])
        (substring str 0 (substring-index " " str)) ) ) ) )


;;; PCRE Types:

(define-foreign-type size_t "size_t")

(define-foreign-type pcre (c-pointer "pcre"))
(define-foreign-type nonnull-pcre (nonnull-c-pointer "pcre"))

(define-foreign-type pcre_extra (c-pointer "pcre_extra"))
(define-foreign-type nonnull-pcre_extra (nonnull-c-pointer "pcre_extra"))

(define-foreign-variable PCRE_CASELESS unsigned-integer)
(define-foreign-variable PCRE_EXTENDED unsigned-integer)
(define-foreign-variable PCRE_UTF8 unsigned-integer)

;FIXME the use of 'define-foreign-enum' causes unused global variable warning!

(define-foreign-enum (pcre-option unsigned-integer)
  (caseless             PCRE_CASELESS)
  (multiline            PCRE_MULTILINE)
  (dotall               PCRE_DOTALL)
  (extended             PCRE_EXTENDED)
  (anchored             PCRE_ANCHORED)
  (dollar-endonly       PCRE_DOLLAR_ENDONLY)
  (extra                PCRE_EXTRA)
  (notbol               PCRE_NOTBOL)
  (noteol               PCRE_NOTEOL)
  (ungreedy             PCRE_UNGREEDY)
  (notempty             PCRE_NOTEMPTY)
  (utf8                 PCRE_UTF8)
  (no-auto-capture      PCRE_NO_AUTO_CAPTURE)
  (no-utf8-check        PCRE_NO_UTF8_CHECK)
  (auto-callout         PCRE_AUTO_CALLOUT)
  (partial              PCRE_PARTIAL)
  (dfa-shortest         PCRE_DFA_SHORTEST)
  (dfa-restart          PCRE_DFA_RESTART)
  (firstline            PCRE_FIRSTLINE)
  (dupnames             PCRE_DUPNAMES)
  (newline-cr           PCRE_NEWLINE_CR)
  (newline-lf           PCRE_NEWLINE_LF)
  (newline-crlf         PCRE_NEWLINE_CRLF)
  (newline-any          PCRE_NEWLINE_ANY)
  (newline-anycrlf      PCRE_NEWLINE_ANYCRLF)
  (bsr-anycrlf          PCRE_BSR_ANYCRLF)
  (bsr-unicode          PCRE_BSR_UNICODE) )

(define pcre-option-symbols '(
  caseless
  multiline
  dotall
  extended
  anchored
  dollar-endonly
  extra
  notbol
  noteol
  ungreedy
  notempty
  utf8
  no-auto-capture
  no-utf8-check
  auto-callout
  partial
  dfa-shortest
  dfa-restart
  firstline
  dupnames
  newline-cr
  newline-lf
  newline-crlf
  newline-any
  newline-anycrlf
  bsr-anycrlf
  bsr-unicode) )

(define-foreign-enum (pcre-info-field unsigned-int)
  (options          PCRE_INFO_OPTIONS)
  (size             PCRE_INFO_SIZE)
  (capturecount     PCRE_INFO_CAPTURECOUNT)
  (backrefmax       PCRE_INFO_BACKREFMAX)
  (firstbyte        PCRE_INFO_FIRSTBYTE)
  (firstchar        PCRE_INFO_FIRSTCHAR)
  (firsttable       PCRE_INFO_FIRSTTABLE)
  (lastliteral      PCRE_INFO_LASTLITERAL)
  (nameentrysize    PCRE_INFO_NAMEENTRYSIZE)
  (namecount        PCRE_INFO_NAMECOUNT)
  (nametable        PCRE_INFO_NAMETABLE)
  (studysize        PCRE_INFO_STUDYSIZE)
  (default-tables   PCRE_INFO_DEFAULT_TABLES)
  (okpartial        PCRE_INFO_OKPARTIAL)
  (jchanged         PCRE_INFO_JCHANGED)
  (hascrorlf        PCRE_INFO_HASCRORLF) )

(define pcre-info-field-types '(
  (options          integer)
  (size             integer)
  (capturecount     integer)
  (backrefmax       integer)
  (firstbyte        integer)
  (firstchar        integer)
  (firsttable       pointer)
  (lastliteral      integer)
  (nameentrysize    integer)
  (namecount        integer)
  (nametable        pointer)
  (studysize        integer)
  (default-tables   pointer)
  (okpartial        boolean)
  (jchanged         boolean)
  (hascrorlf        boolean) ) )

(define-foreign-enum (pcre-config-field unsigned-int)
  (utf8                     PCRE_CONFIG_UTF8)
  (newline                  PCRE_CONFIG_NEWLINE)
  (link-size                PCRE_CONFIG_LINK_SIZE)
  (posix-malloc-threshold   PCRE_CONFIG_POSIX_MALLOC_THRESHOLD)
  (match-limit              PCRE_CONFIG_MATCH_LIMIT)
  (stackrecurse             PCRE_CONFIG_STACKRECURSE)
  (unicode-properties       PCRE_CONFIG_UNICODE_PROPERTIES)
  (match-limit-recursion    PCRE_CONFIG_MATCH_LIMIT_RECURSION)
  (bsr                      PCRE_CONFIG_BSR) )

(define pcre-config-field-types '(
  (utf8                     boolean)
  (newline                  integer)
  (link-size                integer)
  (posix-malloc-threshold   integer)
  (match-limit              integer)
  (stackrecurse             boolean)
  (unicode-properties       boolean)
  (match-limit-recursion    integer)
  (bsr                      boolean) ) )

#; ; UNUSED
(define-foreign-enum (pcre-extra-option unsigned-int)
  (study-data     PCRE_EXTRA_STUDY_DATA)
  (match-limit    PCRE_EXTRA_MATCH_LIMIT)
  (callout-data   PCRE_EXTRA_CALLOUT_DATA)
  (tables         PCRE_EXTRA_TABLES)
  (match-limit    PCRE_EXTRA_MATCH_LIMIT_RECURSION) )


;;; The regexp structure primitives:

(define re-finalizer
  (foreign-lambda void "pcre_free" c-pointer) )

(define-inline (%make-regexp code)
  (set-finalizer! code re-finalizer)
  (##sys#make-structure 'regexp code #f 0) )

(define-inline (%regexp? x)
  (##sys#structure? x 'regexp) )

(define-inline (%regexp-code rx)
  (##sys#slot rx 1) )

(define-inline (%regexp-extra rx)
  (##sys#slot rx 2) )

(define-inline (%regexp-options rx)
  (##sys#slot rx 3) )

(define-inline (%regexp-extra-set! rx extra)
  (when extra (set-finalizer! extra re-finalizer))
  (##sys#setslot rx 2 extra) )

(define-inline (%regexp-options-set! rx options)
  (##sys#setslot rx 3 options) )


;;; Regexp record:

(define (regexp? x)
  (%regexp? x) )


;;; PCRE errors:

(foreign-declare #<<EOF
static const char *C_regex_error;
static int C_regex_error_offset;
EOF
)

(define-foreign-variable C_regex_error c-string)
(define-foreign-variable C_regex_error_offset int)

(define re-error
  (let ([string-append string-append])
    (lambda (loc msg . args)
      (apply ##sys#error loc (string-append msg " - " C_regex_error) args) ) ) )

;;; Compile regular expression:

;FIXME nonnull-unsigned-c-string causes problems - converted string is too long!

(define re-compile
  (foreign-lambda* pcre ((nonnull-c-string patt) (unsigned-integer options) ((const (c-pointer unsigned-char)) tables))
    "return(pcre_compile(patt, options, &C_regex_error, &C_regex_error_offset, tables));") )

(define (re-checked-compile pattern options tables loc)
  (##sys#check-string pattern loc)
  (or (re-compile pattern options #f)
      (re-error loc "cannot compile regular expression" pattern C_regex_error_offset) ) )

;; Compile with subset of options and no tables

(define (regexp pattern . options)
  (let ([options->integer
          (lambda ()
            (if (null? options)
                0
                (+ (if (car options) PCRE_CASELESS 0)
                   (let ((options (cdr options)))
                     (if (null? options)
                         0
                         (+ (if (car options) PCRE_EXTENDED 0)
                            (let ((options (cdr options)))
                              (if (and (pair? options) (car options)) PCRE_UTF8 0 ) ) ) ) ) ) ) )])
    (%make-regexp (re-checked-compile pattern (options->integer) #f 'regexp)) ) )

;; Compile with full options and tables available

(define (regexp* pattern . args)
  (let-optionals args ([options '()] [tables #f])
    (##sys#check-string pattern 'regexp*)
    (##sys#check-list options 'regexp*)
    (when tables (check-chardef-table tables 'regexp*))
    (%make-regexp (re-checked-compile pattern (pcre-option->number options) tables 'regexp*)) ) )


;;; Character Definition Tables:

(foreign-declare "#include \"pcre/pcre_internal.h\"")

;;

(define (re-chardef-table tables)
  (%tag-pointer tables 'chardef-table) )

;; Make character definition tables

(define re-maketables
  (foreign-lambda* (const (nonnull-c-pointer unsigned-char)) ()
    "const unsigned char *tables = pcre_maketables();"
    "if (!tables) out_of_memory_failure(\"regex\", \"re-maketables\", \"tables\");"
    "return(tables);"))

;; Get a character definitions tables structure for the current locale.

(define (regex-chardef-table)
  (let ([tables (re-chardef-table (re-maketables))])
    (set-finalizer! tables re-finalizer)
    tables ) )

;; Is it a character definitions tables structure

(define (regex-chardef-table? x)
  (%tagged-pointer? x 'chardef-table) )

;; Valid character definitions tables structure

(define (check-chardef-table x loc)
  (unless (regex-chardef-table? x)
    (##sys#error loc "invalid character definition tables structure" x) ) )

;; Character Class

(define-foreign-enum (pcre-cbit unsigned-int)
  (space cbit_space)
  (xdigit cbit_xdigit)
  (digit cbit_digit)
  (upper cbit_upper)
  (lower cbit_lower)
  (word cbit_word)
  (graph cbit_graph)
  (print cbit_print)
  (punct cbit_punct)
  (cntrl cbit_cntrl) )

(define cbit-symbols '(space xdigit digit upper lower word graph print punct cntrl))

;; Character Type

(define-foreign-enum (pcre-ctype unsigned-int)
  (space ctype_space)
  (letter ctype_letter)
  (digit ctype_digit)
  (xdigit ctype_xdigit)
  (word ctype_word)
  (meta ctype_meta) )

(define ctype-symbols '(space xdigit digit letter word meta))

;; Accessors

(define chardef-lower-case-set!
  (foreign-lambda* void (((c-pointer unsigned-char) tables) (int idx) (unsigned-char lower))
    "tables[lcc_offset + idx] = lower;"))

(define chardef-lower-case
  (foreign-lambda* unsigned-int (((const (c-pointer unsigned-char)) tables) (int idx))
    "return(tables[lcc_offset + idx]);"))

(define chardef-flipped-case-set!
  (foreign-lambda* void (((c-pointer unsigned-char) tables) (int idx) (unsigned-char flipped))
    "tables[fcc_offset + idx] = flipped;"))

(define chardef-flipped-case
  (foreign-lambda* unsigned-int (((const (c-pointer unsigned-char)) tables) (int idx))
    "return(tables[fcc_offset + idx]);"))

(define chardef-class-clear!
  (foreign-lambda* void (((c-pointer unsigned-char) tables) (int idx) (unsigned-int class))
    "tables[cbits_offset + class + idx/8] &= ~(1 << (idx & 7));"))

(define chardef-class-set!
  (foreign-lambda* void (((c-pointer unsigned-char) tables) (int idx) (unsigned-int class))
    "tables[cbits_offset + class + idx/8] |= 1 << (idx & 7);"))

(define chardef-class
  (foreign-lambda* unsigned-int (((const (c-pointer unsigned-char)) tables) (int idx) (unsigned-int class))
    "return(tables[cbits_offset + class + idx/8] & (1 << (idx & 7)));"))

(define (chardef-classes-clear! tables idx)
  (for-each
    (lambda (sym)
      (chardef-class-clear! tables idx (pcre-cbit->number sym)))
    cbit-symbols) )

(define chardef-type-clear!
  (foreign-lambda* void (((c-pointer unsigned-char) tables) (int idx))
    "tables[ctypes_offset + idx] = 0;"))

(define chardef-type-set!
  (foreign-lambda* void (((c-pointer unsigned-char) tables) (int idx) (unsigned-int type))
    "tables[ctypes_offset + idx] += type;"))

(define chardef-type
  (foreign-lambda* unsigned-int (((const (c-pointer unsigned-char)) tables) (int idx) (unsigned-int type))
    "return(tables[ctypes_offset + idx] & type);"))

;; Update a character definition.
;;
;; 'tables' is a character definition tables structure
;; 'chardef' is a length 4 vector where
;; element 0 is the lower-case character or #f
;; element 1 is the flipped-case character or #f
;; element 2 is a list of character class names or #f
;; element 3 is a list of character type names or #f

(define (regex-chardef-set! tables idx-or-char chardef)
  ; Check proper character definition tables structure
  (check-chardef-table tables 'regex-chardef-set!)
  ; Need character table index
  (let ([idx (if (char? idx-or-char) (char->integer idx-or-char) idx-or-char)])
    ; Check proper index
    (##sys#check-exact idx 'regex-chardef-set!)
    (unless (and (fx<= 0 idx) (fx<= idx 255))
      (##sys#error 'regex-chardef-set! "invalid character index - must be in [0 255]" idx) )
    ; Check proper character definition structure
    (##sys#check-vector chardef 'regex-chardef-set!)
    (unless (fx= 4 (vector-length chardef))
      (##sys#error 'regex-chardef-set! "invalid chardef length - must be 4" chardef) )
    ; Change lower case character?
    (and-let* ([lower (vector-ref chardef 0)])
      (chardef-lower-case-set! tables idx lower) )
    ; Change flipped case character?
    (and-let* ([flipped (vector-ref chardef 1)])
       (chardef-flipped-case-set! tables idx flipped) )
    ;
    (let ([set-symbols
            (lambda (syms clear sym->num set)
              (##sys#check-list syms 'regex-chardef-set!)
              (clear tables idx)
              (for-each
                (lambda (sym)
                  (set tables idx (sym->num sym)))
                syms) )])
      ; Change character class?
      (and-let* ([cbits (vector-ref chardef 2)])
        (set-symbols cbits chardef-classes-clear! pcre-cbit->number chardef-class-set!) )
      ; Change character type?
      (and-let* ([ctypes (vector-ref chardef 3)])
        (set-symbols ctypes chardef-type-clear! pcre-ctype->number chardef-type-set!) ) ) ) )

;; Update character definition tables.
;;
;; 'tables' is a character definition tables structure
;; 'chardefs' is a length 256 vector of #f or character definitions

(define (regex-chardefs-update! tables chardefs)
  ; Check proper character definition tables structure
  (check-chardef-table tables 'regex-chardef-update!)
  ; Check proper character definition table structure
  (##sys#check-vector chardefs 'regex-chardefs-update!)
  (unless (fx= 256 (vector-length chardefs))
    (##sys#error 'regex-chardefs-update! "invalid chardefs length - must be 256" chardefs) )
  ; Set every character definition
  (do ([idx 0 (fx+ idx 1)])
      [(fx= 256 idx)]
    ; When a new character definition
    (and-let* ([chardef (vector-ref chardefs idx)])
      (regex-chardef-set! tables idx chardef) ) ) )

;; Get the character definitions.
;; Returns a character definitions vector.

(define (regex-chardefs tables)
  ; Check proper character definition tables structure
  (check-chardef-table tables 'regex-chardefs)
  ; 256 character definitions
  (let ([chardefs (make-vector 256)])
    ; Get every character definition
    (do ([idx 0 (fx+ idx 1)])
        [(fx= 256 idx) chardefs]
      ; This character definition
      (let ([chardef (make-vector 4)])
        (vector-set! chardefs idx chardef)
        ; Lower-case
        (vector-set! chardef 0 (integer->char (chardef-lower-case tables idx)))
        ; Flipped-case
        (vector-set! chardef 1 (integer->char (chardef-flipped-case tables idx)))
        ;
        (let ([get-symbols
                (lambda (syms get sym->num)
                  (let loop ([syms syms]
                             [lst '()])
                    (if (null? syms)
                        lst
                        (let ([sym (car syms)])
                          (loop (cdr syms)
                                (if (fx= 0 (get tables idx (sym->num sym)))
                                    lst
                                    (cons sym lst) ) ) ) ) ) )])
          ; Character class
          (vector-set! chardef 2 (get-symbols cbit-symbols chardef-class pcre-cbit->number))
          ; Character type
          (vector-set! chardef 3 (get-symbols ctype-symbols chardef-type pcre-ctype->number)) ) ) ) ) )


;;; Optimize compiled regular expression:

;; Create optimization structure

(define re-extra
  ; Only the flags need to be initialized
  ; When a flag bit is 0 the corresponding field is ignored
  (foreign-lambda* nonnull-pcre_extra ()
    "pcre_extra *extra = (pcre_extra *)(pcre_malloc)(sizeof(pcre_extra));"
    "if (!extra) out_of_memory_failure(\"regex\", \"re-extra\", \"pcre_extra\");"
    "extra->flags = 0;"
    "extra->study_data = NULL;"
    "extra->match_limit = 0;"
    "extra->match_limit_recursion = 0;"
    "extra->callout_data = NULL;"
    "extra->tables = NULL;"
    "return(extra);"))

;; Set specific field

(define (re-extra-field-set! loc extra key val)
  (case key
    [(match-limit)
      (##sys#check-exact match-limit loc)
      ((foreign-lambda* void ((nonnull-pcre_extra extra) (unsigned-long val))
          "extra->match_limit = val;"
          "extra->flags |= PCRE_EXTRA_MATCH_LIMIT;")
        extra val)]
    [(match-limit-recursion)
      (##sys#check-exact match-limit-recursion loc)
      ((foreign-lambda* void ((nonnull-pcre_extra extra) (unsigned-long val))
          "extra->match_limit_recursion = val;"
          "extra->flags |= PCRE_EXTRA_MATCH_LIMIT_RECURSION;")
        extra val)]
    [(callout-data)
      (##sys#check-blob callout-data loc)
      ((foreign-lambda* void ((nonnull-pcre_extra extra) (nonnull-byte-vector val))
          "extra->callout_data = val;"
          "extra->flags |= PCRE_EXTRA_CALLOUT_DATA;")
        extra val)]
    [(tables)
      (check-chardef-table tables loc)
      ((foreign-lambda* void ((nonnull-pcre_extra extra) ((const (c-pointer unsigned-char)) val))
          "extra->tables = val;"
          "extra->flags |= PCRE_EXTRA_TABLES;")
        extra val)]
    [else
      (warning loc "unrecognized extra field key" key)] ) )

;; Set fields

(define (re-extra-fields-set! loc extra . args)
  (let loop ([args args])
    (unless (null? args)
      (let ([key (car args)]
            [val (cadr args)])
        (re-extra-field-set! loc extra key val)
        (loop (cddr args)) ) ) ) )

;; Set user override fields

(define (regexp-optimization-set! rx . args)
  (##sys#check-structure rx 'regexp 'regexp-extras)
  (apply re-extra-fields-set! 'regexp-optimization-set!
                              (or (%regexp-extra rx)
                                  (let ([extra (re-extra)]) (%regexp-extra-set! rx extra) extra))
                              args) )

;; Invoke optimizer

(define re-study
  (foreign-lambda* pcre_extra (((const nonnull-pcre) code))
    "return(pcre_study(code, 0, &C_regex_error));"))

;; Optimize compiled regular expression
;; Returns whether optimization performed

(define (regexp-optimize rx . args)
  (##sys#check-structure rx 'regexp 'regexp-optimize)
  (let ([extra (re-study (%regexp-code rx))])
    (cond [C_regex_error
            (re-error 'regexp-optimize "cannot optimize regular expression" rx)]
          [extra
            (%regexp-extra-set! rx extra)
            (unless (null? args) (apply re-extra-fields-set! 'regexp-optimize extra args))
            #t]
          [else
            #f] ) ) )

;;

(define (re-extra-field loc extra key)
  (case key
    [(match-limit)
      ((foreign-lambda* void ((nonnull-pcre_extra extra) (unsigned-long val))
          "return(extra->match_limit);")
        extra)]
    [(match-limit-recursion)
      ((foreign-lambda* void ((nonnull-pcre_extra extra) (unsigned-long val))
          "return(extra->match_limit_recursion);")
        extra)]
    [(callout-data)
      ((foreign-lambda* void ((nonnull-pcre_extra extra) (nonnull-byte-vector val))
          "return(extra->callout_data);")
        extra)]
    [(tables)
      (re-chardef-table
        ((foreign-lambda* void ((nonnull-pcre_extra extra) ((const (c-pointer unsigned-char)) val))
            "return(extra->tables);")
          extra))]
    [else
      (warning loc "unrecognized extra field key" key)] ) )

;;

(define (regexp-extra-info rx . fields)
  (##sys#check-structure rx 'regexp 'regexp-extra-info)
  (let ([extra (%regexp-extra fx)])
    (if extra
        (map
          (lambda (sym)
            (##sys#check-symbol sym 'regexp-extra-info)
            (list sym (re-extra-field 'regexp-extra-info extra sym)) )
          fields)
        '() ) ) )


;;; Regexp options:

;; Get a list of option symbols from the integer options

(define (options->symbols options)
  (let ([lst '()])
    (for-each
      (lambda (sym)
        (unless (zero? (bitwise-and options (pcre-option->number sym)))
          (set! lst (cons sym lst)) ) )
      pcre-option-symbols)
    lst ) )

;; Set the 'exec' options

(define (set-regexp-options! rx . options)
  (##sys#check-structure rx 'regexp 'regexp-options-set!)
  (%regexp-options-set! rx (pcre-option->number options)) )

;; Ref the 'exec' options

(define (regexp-options rx)
  (options->symbols
    (cond [(%regexp? obj)   (%regexp-options obj)]
          [(integer? obj)   obj]
          [else
            (##sys#signal-hook #:type-error
                               'regexp-options
                     "bad argument type - not an integer or compiled regular expression"
                     obj)] ) ) )


;;; Regexp 'fullinfo':

(define re-info-integer
  (foreign-lambda* unsigned-integer (((const nonnull-pcre) code) (pcre_extra extra) (int fieldno))
    "int val;"
    "pcre_fullinfo(code, extra, fieldno, &val);"
    "return(val);") )

(define re-info-boolean
  (foreign-lambda* bool (((const nonnull-pcre) code) (pcre_extra extra) (int fieldno))
    "int val;"
    "pcre_fullinfo(code, extra, fieldno, &val);"
    "return(val);") )

(define re-info-pointer
  (foreign-lambda* c-pointer (((const nonnull-pcre) code) (pcre_extra extra) (int fieldno))
    "void *val;"
    "pcre_fullinfo(code, extra, fieldno, &val);"
    "return(val);") )

;;

(define (regexp-info rx . fields)
  (##sys#check-structure rx 'regexp 'regexp-info)
  (let ([code (%regexp->code rx)]
        [extra (%regexp->extra rx)])
    (map
      (lambda (sym)
        (##sys#check-symbol sym 'regexp-info)
        (list sym
              (and-let* ([ent (alist-ref sym pcre-info-field-types)])
                (let ([fldno (pcre-info-field->number sym)])
                  (case (cadr ent)
                    [(boolean)
                      (re-info-boolean code extra fldno)]
                    [(integer)
                      (re-info-integer code extra fldno)]
                    [(pointer)
                      (let ([ptr (re-info-pointer code extra fldno)])
                        (case sym
                          [(default-tables firsttable)
                            (re-chardef-table ptr)]
                          [else
                            ptr] ) ) ] ) ) ) ) )
      fields) ) )

;;

(foreign-declare #<<EOF

typedef struct {
  char *nametable;
  int entrysize;
} pcre_nametable;

static int
get_nametable_entrycount(const pcre *code, const pcre_extra *extra)
{
  int val;
  pcre_fullinfo(code, extra, PCRE_INFO_NAMECOUNT, &val);
  return val;
}

static pcre_nametable *
get_nametable(const pcre *code, const pcre_extra *extra)
{
  pcre_nametable *nametable = (pcre_nametable *)(pcre_malloc)(sizeof(pcre_nametable));
  if (!nametable) out_of_memory_failure("regex", "pcre_nametable", "pcre_nametable");
  pcre_fullinfo(code, extra, PCRE_INFO_NAMETABLE, &nametable->nametable);
  pcre_fullinfo(code, extra, PCRE_INFO_NAMEENTRYSIZE, &nametable->entrysize);
  return nametable;
}

static char *
get_nametable_entry(const pcre_nametable *nt, int idx, int *pcc)
{
  typedef struct {
    uint16_t cc;
    char name[1];
  } pcre_nametable_entry;

  pcre_nametable_entry *entry = ((pcre_nametable_entry *)(nt->nametable)) + (idx * nt->entrysize);
  /* Number of capturing parentheses is MSB */
# ifdef C_LITTLE_ENDIAN
  uint16_t cc;
  ((uint8_t *)&cc)[0] = ((uint8_t *)&entry->cc)[1];
  ((uint8_t *)&cc)[1] = ((uint8_t *)&entry->cc)[0];
  *pcc = cc;
# else
  *pcc = entry->cc;
# endif
  return entry->name;
}
EOF
)

(define-foreign-type pcre_nametable (nonnull-c-pointer "pcre_nametable"))

(define re-nametable-entrycount
  (foreign-lambda int "get_nametable_entrycount" (const nonnull-pcre) (const pcre_extra)))

(define re-nametable
  (foreign-lambda nonnull-c-pointer "get_nametable" (const nonnull-pcre) (const pcre_extra)))

(define re-nametable-entry
  (foreign-lambda nonnull-c-string "get_nametable_entry" (const pcre_nametable) int (c-pointer int)))

(define (regexp-info-nametable rx)
  (##sys#check-structure rx 'regexp 'regexp-info-nametable)
  (let ([code (%regexp->code rx)]
        [extra (%regexp->extra rx)])
    (let ([cnt (re-nametable-entrycount code extra)])
      (unless (fx= 0 cnt)
        (let ([nt (re-nametable code extra)])
          (set-finalizer! nt re-finalizer)
          (let loop ([idx 0] [lst '()])
            (if (fx= cnt idx)
                lst
                (let-location ([cc int])
                (let ([nam (re-nametable-entry nt idx #$cc)])
                  (loop (fx+ idx 1) (cons (list nam idx cc) lst)) ) ) ) ) ) ) ) ) )


;;; PCRE config info:

;;

(define config-info-integer
  (foreign-lambda* unsigned-integer ((int fieldno))
    "int val;"
    "pcre_config(fieldno, &val);"
    "return(val);") )

(define config-info-boolean
  (foreign-lambda* bool ((int fieldno))
    "int val;"
    "pcre_config(fieldno, &val);"
    "return(val);") )

;;

(define (pcre-config-info . fields)
  (map
    (lambda (sym)
      (##sys#check-symbol sym 'pcre-config-info)
      (list sym
            (and-let* ([ent (alist-ref sym pcre-config-field-types)])
              (let ([fldno (pcre-config-field->number sym)])
                (case (cadr ent)
                  [(boolean)
                    (config-info-boolean fldno)]
                  [(integer)
                    (let ([int (config-info-integer fldno)])
                      (if (eq? 'newline sym)
                          (integer->char int)
                          int ) ) ] ) ) ) ) )
    fields) )


;;; Captured results vector:

;; Match positions vector (PCRE ovector)

(foreign-declare #<<EOF
#define OVECTOR_LENGTH_MULTIPLE 3
#define STATIC_OVECTOR_LEN 256
static int C_regex_ovector[OVECTOR_LENGTH_MULTIPLE * STATIC_OVECTOR_LEN];
EOF
)

;;

(define ovector-start-ref
  (foreign-lambda* int ((int i))
    "return(C_regex_ovector[i * 2]);") )

(define ovector-end-ref
  (foreign-lambda* int ((int i))
    "return(C_regex_ovector[(i * 2) + 1]);") )


;;; Gather matched result strings or positions:

(define (gather-result-positions result)
  (let ([mc (car result)]
        [cc (cadr result)])
    (and (fx> mc 0)
         (let loop ([i 0])
           (cond [(fx>= i cc)
                   '()]
                 [(fx>= i mc)
                   (cons #f (loop (fx+ i 1)))]
                 [else
                  (let ([start (ovector-start-ref i)])
                    (cons (and (fx>= start 0)
                               (list start (ovector-end-ref i)))
                          (loop (fx+ i 1)) ) ) ] ) ) ) ) )

(define gather-results
  (let ([substring substring])
    (lambda (str result)
      (let ([ps (gather-result-positions result)])
        (and ps
             (##sys#map (lambda (poss) (and poss (apply substring str poss))) ps) ) ) ) ) )


;;; Common match string with compile regular expression:

(define re-match
  (foreign-lambda* int (((const nonnull-pcre) code) ((const pcre_extra) extra)
                        (nonnull-c-string str) (int start) (int range)
                        (unsigned-integer options))
    "return(pcre_exec(code, extra, str, start + range, start, options, C_regex_ovector, STATIC_OVECTOR_LEN * OVECTOR_LENGTH_MULTIPLE));") )

(define re-match-capture-count
  (foreign-lambda* int (((const nonnull-pcre) code) ((const pcre_extra) extra))
    "int cc;"
    "pcre_fullinfo(code, extra, PCRE_INFO_CAPTURECOUNT, &cc);"
    "return(cc + 1);") )

(define (perform-match rgxp str si ri loc)
  (let* ([extra #f]
         [options 0]
         [rx
          (cond [(string? rgxp)
                  (re-checked-compile rgxp 0 #f loc)]
                [(%regexp? rgxp)
                  (set! extra (%regexp-extra rgxp))
                  (set! options (%regexp-options rgxp))
                  (%regexp-code rgxp)]
                [else
                  (##sys#signal-hook #:type-error
                                     loc
                                     "bad argument type - not a string or compiled regular expression"
                                     rgxp)] )]
         [cc (re-match-capture-count rx extra)]
         [mc (re-match rx extra str si ri options)])
    (when (string? rgxp) (re-finalizer rx))
    (list mc cc) ) )


;;; Match string with regular expression:

;; Note that start is a BYTE offset

(define string-match)
(define string-match-positions)
(let ()

  (define (prepare-match rgxp str start loc)
    (##sys#check-string str loc)
    (let ([si (if (pair? start) (car start) 0)])
      (##sys#check-exact si loc)
      (perform-match (if (string? rgxp)
                         (make-anchored-pattern rgxp (fx< 0 si))
                         rgxp)
                     str si (fx- (##sys#size str) si)
                     loc) ) )

  (set! string-match
    (lambda (rgxp str . start)
      (gather-results str (prepare-match rgxp str start 'string-match)) ) )

  (set! string-match-positions
    (lambda (rgxp str . start)
      (gather-result-positions (prepare-match rgxp str start 'string-match-positions)) ) ) )


;;; Search string with regular expression:

;; Note that start & range are BYTE offsets


(define string-search)
(define string-search-positions)
(let ()

  (define (prepare-search rgxp str start-and-range loc)
    (##sys#check-string str loc)
    (let* ([range (and (pair? start-and-range) (cdr start-and-range)) ]
           [si (if range (car start-and-range) 0)]
           [ri (if (pair? range) (car range) (fx- (##sys#size str) si))] )
      (##sys#check-exact si loc)
      (##sys#check-exact ri loc)
      (perform-match rgxp str si ri loc) ) )

  (set! string-search
    (lambda (rgxp str . start-and-range)
      (gather-results str (prepare-search rgxp str start-and-range 'string-search)) ) )

  (set! string-search-positions
    (lambda (rgxp str . start-and-range)
      (gather-result-positions (prepare-search rgxp str start-and-range 'string-search-positions)) ) ) )


;;; Split string into fields:

(define string-split-fields
  (let ([reverse reverse]
        [substring substring]
        [string-search-positions string-search-positions] )
    (lambda (rgxp str . mode-and-start)
      (##sys#check-string str 'string-split-fields)
      (let* ([argc (length mode-and-start)]
             [len (##sys#size str)]
             [mode (if (fx> argc 0) (car mode-and-start) #t)]
             [start (if (fx> argc 1) (cadr mode-and-start) 0)]
             [fini (case mode
                     [(#:suffix)
                      (lambda (ms start)
                        (if (fx< start len)
                            (##sys#error 'string-split-fields
                                         "record does not end with suffix" str rgxp)
                            (reverse ms) ) ) ]
                     [(#:infix)
                      (lambda (ms start)
                        (if (fx>= start len)
                            (reverse (cons "" ms))
                            (reverse (cons (substring str start len) ms)) ) ) ]
                     [else (lambda (ms start) (reverse ms)) ] ) ]
             [fetch (case mode
                      [(#:infix #:suffix) (lambda (start from to) (substring str start from))]
                      [else (lambda (start from to) (substring str from to))] ) ] )
        (let loop ([ms '()] [start start])
          (let ([m (string-search-positions rgxp str start)])
            (if m
                (let* ([mp (car m)]
                       [from (car mp)]
                       [to (cadr mp)] )
                  (if (fx= from to)
                      (if (fx= to len)
                          (fini ms start)
                          (loop (cons (fetch start (fx+ from 1) (fx+ to 2)) ms) (fx+ to 1)) )
                      (loop (cons (fetch start from to) ms) to) ) )
                (fini ms start) ) ) ) ) ) ) )


;;; Substitute matching strings:

(define string-substitute
  (let ([substring substring]
        [reverse reverse]
        [make-string make-string]
        [string-search-positions string-search-positions] )
    (lambda (regex subst string . flag)
      (##sys#check-string subst 'string-substitute)
      (let* ([which (if (pair? flag) (car flag) 1)]
             [substlen (##sys#size subst)]
             [substlen-1 (fx- substlen 1)]
             [result '()]
             [total 0] )
        (define (push x)
          (set! result (cons x result))
          (set! total (fx+ total (##sys#size x))) )
        (define (substitute matches)
          (let loop ([start 0] [index 0])
            (if (fx>= index substlen-1)
                (push (if (fx= start 0) subst (substring subst start substlen)))
                (let ([c (##core#inline "C_subchar" subst index)]
                      [index+1 (fx+ index 1)] )
                  (if (char=? c #\\)
                      (let ([c2 (##core#inline "C_subchar" subst index+1)])
                        (if (and (not (char=? #\\ c2)) (char-numeric? c2))
                            (let ([mi (list-ref matches (fx- (char->integer c2) 48))])
                              (push (substring subst start index))
                              (push (substring string (car mi) (cadr mi)))
                              (loop (fx+ index 2) index+1) )
                            (loop start (fx+ index+1 1)) ) )
                      (loop start index+1) ) ) ) ) )
        (let loop ([index 0] [count 1])
          (let ([matches (string-search-positions regex string index)])
            (cond [matches
                   (let* ([range (car matches)]
                          [upto (cadr range)] )
                     (cond ((fx= 0 (fx- (cadr range) (car range)))
                            (##sys#error
                             'string-substitute "empty substitution match"
                             regex) )
                           ((or (not (fixnum? which)) (fx= count which))
                            (push (substring string index (car range)))
                            (substitute matches)
                            (loop upto #f) )
                           (else
                            (push (substring string index upto))
                            (loop upto (fx+ count 1)) ) ) ) ]
                  [else
                   (push (substring string index (##sys#size string)))
                   (##sys#fragments->string total (reverse result)) ] ) ) ) ) ) ) )

(define string-substitute*
  (let ([string-substitute string-substitute])
    (lambda (str smap . mode)
      (##sys#check-string str 'string-substitute*)
      (##sys#check-list smap 'string-substitute*)
      (let ((mode (and (pair? mode) (car mode))))
        (let loop ((str str) (smap smap))
          (if (null? smap)
              str
              (let ((sm (car smap)))
                (loop (string-substitute (car sm) (cdr sm) str mode)
                      (cdr smap) ) ) ) ) ) ) ) )


;;; Glob support:

;FIXME is it worthwhile making this accurate?
(define (glob? str)
  (##sys#check-string str 'glob?)
  (let loop ([idx (fx- (string-length str) 1)])
    (and (fx<= 0 idx)
         (case (string-ref str idx)
           [(#\* #\] #\?)
             (or (fx= 0 idx)
                 (not (char=? #\\ (string-ref str (fx- idx 1))))
                 (loop (fx- idx 2)))]
           [else
             (loop (fx- idx 1))]) ) ) )

(define glob->regexp
  (let ([list->string list->string]
        [string->list string->list] )
    (lambda (s)
      (##sys#check-string s 'glob->regexp)
      (list->string
       (let loop ((cs (string->list s)))
         (if (null? cs)
             '()
             (let ([c (car cs)]
                   [rest (cdr cs)] )
               (cond [(char=? c #\*)  `(#\. #\* ,@(loop rest))]
                     [(char=? c #\?)  (cons '#\. (loop rest))]
                     [(char=? c #\[)
                      (cons
                       #\[
                       (let loop2 ((rest rest))
                         (match rest
                           [(#\] . more)        (cons #\] (loop more))]
                           [(#\- c . more)      `(#\- ,c ,@(loop2 more))]
                           [(c1 #\- c2 . more)  `(,c1 #\- ,c2 ,@(loop2 more))]
                           [(c . more)          (cons c (loop2 more))]
                           [()
                            (error 'glob->regexp "unexpected end of character class" s)] ) ) ) ]
                     [(or (char-alphabetic? c) (char-numeric? c)) (cons c (loop rest))]
                     [else `(#\\ ,c ,@(loop rest))] ) ) ) ) ) ) ) )


;;; Grep-like function on list:

(define grep
  (let ([string-search string-search])
    (lambda (rgxp lst)
      (##sys#check-list lst 'grep)
      (let loop ([lst lst])
        (if (null? lst)
            '()
            (let ([x (car lst)]
                  [r (cdr lst)] )
              (if (string-search rgxp x)
                  (cons x (loop r))
                  (loop r) ) ) ) ) ) ) )


;;; Escape regular expression (suggested by Peter Bex):

(define regexp-escape
  (let ([open-output-string open-output-string]
        [get-output-string get-output-string] )
    (lambda (str)
      (##sys#check-string str 'regexp-escape)
      (let ([out (open-output-string)]
            [len (##sys#size str)] )
        (let loop ([i 0])
          (cond [(fx>= i len) (get-output-string out)]
                [(memq (##core#inline "C_subchar" str i)
                       '(#\. #\\ #\? #\* #\+ #\^ #\$ #\( #\) #\[ #\] #\| #\{ #\}))
                 (##sys#write-char-0 #\\ out)
                 (##sys#write-char-0 (##core#inline "C_subchar" str i) out)
                 (loop (fx+ i 1)) ]
                [else
                 (##sys#write-char-0 (##core#inline "C_subchar" str i) out)
                 (loop (fx+ i 1)) ] ) ) ) ) ) )


;;; Anchored pattern:

(define make-anchored-pattern
  (let ([string-append string-append])
    (lambda (rgxp . args)
      (let-optionals args ([nos #f] [noe #f])
        (cond [(string? rgxp)
                (string-append (if nos "" "^") rgxp (if noe "" "$"))]
              [else
                (##sys#check-structure rgxp 'regexp 'make-anchored-pattern)
                (when (or nos noe)
                  (warning 'make-anchored-pattern
                           "cannot select partial anchor for compiled regular expression") )
                (%regexp-options-set! rgxp
                                      (bitwise-or (%regexp-options regexp)
                                                  (pcre-option->number 'anchored)))
                rgxp] ) ) ) ) )
