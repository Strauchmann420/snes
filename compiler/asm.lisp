"This is the code that actually creates the textual asm output.  "

(in-package #:cs400-compiler)

(always-eval
  (defparameter *annotations* nil))

(defparameter +addressing-modes-and-syntax+
  '((:implied "")
    (:accumulator "A")
    (:immediate "#b")
    (:immediate-w "#w")
    #| TODO What are the other kinds of 'immediate's? |#
    (:direct "b")
    (:direct-x-indexed "b,X")
    (:direct-y-indexed "b,Y")
    (:stack-indexed "b,S")
    (:direct-indirect "(b)")
    (:direct-indirect-long "[b]")
    (:direct-x-indexed-indirect "(b,X)")
    (:direct-indirect-y-indexed "(b),Y")
    (:direct-indirect-long-y-indexed "[b],Y")
    (:stack-relative-indirect-y-indexed "(b,S),Y")
    (:block-move "b,b")
    (:absolute "w")
    (:absolute-x-indexed "w,X")
    (:absolute-y-indexed "w,Y")
    (:absolute-indirect "(w)")
    (:absolute-indirect-long "[w]")
    (:absolute-x-indexed-indirect "(w,X)")
    (:long "l")
    (:long-x-indexed "l,X")))

(defvar *emit-indentation* 0)

(defun indent-chars ()
  (collecting
    (dotimes (i (* 4 *emit-indentation*))
      (collect #\space))))

(defun emit (string)
  (format t "~{~a~}; ~a~%" (indent-chars) string)
  (values))

(defmacro with-indent (name &body code)
  (if *annotations*
      `(let ((*emit-indentation* (1+ *emit-indentation*)))
         (format t "~{~a~}~a~%" (rest (indent-chars)) ',name)
         ,@code)
      `(progn
         ,@code)))

(defun asm-subformat (format-char argument)
  (etypecase argument
    (symbol (symbol-name argument))
    (number (format nil (ecase format-char
                          (#\b "$~2,'0xb")
                          (#\w "$~4,'0xw")
                          (#\l "$~6,'0xl"))
                    argument))))

(defun asm-format (format-string &rest arguments)
  "Take an asm form from +addressing-modes-and-syntax+ and some arguements,
   returning the corresponding asm syntax.  "
  (coerce (flatten
           (loop for char across format-string
              collect (if (find char '(#\b #\w #\l))
                          (coerce (asm-subformat char (pop arguments)) 'list)
                          (list char))))
          'string))

(defun asm (command mode &rest args)
  (declare (keyword command mode))
  (emit (format nil "~a ~a"
                (symbol-name command)
                (apply
                 #'asm-format
                 (car (elookup mode +addressing-modes-and-syntax+))
                 args))))


"# Code Generation Routines"
(always-eval
  #.`(progn ,@(mapcar (fn1 (let* ((n (symbol-name !1))
                                  (p (symbol-package !1))
                                  (fn (intern (format nil "%~a" n) p)))
                             `(defun ,fn (label)
                                (emit (format nil ,(string-upcase
                                                    (format nil "~a {~~a}" n))
                                              label)))))
                      '(beq bne bmi bpl bra))))

(defun %label (name) (emit (format nil "{~a}" name)))
(defun %goto (label-name) (%bra label-name))
(defun %branch-if-not (label-name) (%beq label-name))

(defun %asm-code (symbol &key (prototype nil))
  (emit
   (format nil (if prototype "#Code w ~a" "#Code w {~a}")
           (symbol-name symbol))))

(defmacro 16-bit-mode () `(asm :rep :immediate #x30))
(defmacro 8-bit-mode () `(asm :sep :immediate #x30))

(defun %load-number (x)
  (declare (number x))
  (asm :lda :immediate-w x))

(defmacro write-w (addr value)
  `(progn (asm :lda :immediate-w ,value)
          (asm :sta :direct ,addr)))

(defun set-reset-handler (value)
  (emit (format nil
                "#Data $00:FFFC _reset_handler {~a $0000}"
                value)))

(defun %grow-stack (amount)
  (when (plusp amount)
    (with-indent "_growing_the_stack"
      (asm :tsc :implied)
      (asm :sec :implied)
      (asm :sbc :immediate-w amount)
      (asm :tcs :implied))))

(defun %shrink-stack (amount)
  (when (plusp amount)
    (with-indent "_shrinking_the_stack"
      (asm :tsc :implied)
      (asm :clc :implied)
      (asm :adc :immediate-w amount)
      (asm :tcs :implied))))

(defun %store-addr (address storage-class)
  (ecase storage-class
    (:stack (asm :sta :stack-indexed address))
    (:global (asm :sta :absolute address))))

(defun %load-addr (address storage-class)
  (ecase storage-class
    (:stack (asm :lda :stack-indexed address))
    (:global (asm :lda :absolute address))))

(defun %switch-jump-entry (value target)
  (declare (symbol target) (number value))
  (%cmp value)
  (%beq target))

(defun %sta (operand)
  (declare (list operand))
  (apply #'%store-addr (reverse operand)))

(defun %lda (operand)
  (fare-matcher:match operand
    ((of-type number) (%load-number operand))
    ((list storage-class addr) (%load-addr addr storage-class))))

(defun %cmp (operand)
  (fare-matcher:match operand
    ((of-type number) (asm :cmp :immediate-w operand))
    ((list storage-class addr)
     (ecase storage-class
       (:stack (asm :cmp :stack-indexed addr))
       (:global (asm :cmp :absolute addr))))))

(defun %goto-if-== (x y label)
  (%lda x) (%cmp y) (%beq label))
(defun %goto-if-!= (x y label)
  (%lda x) (%cmp y) (%bne label))
(defun %goto-if->= (x y label)
  (%lda x) (%cmp y) (%bmi label) (%beq label))
(defun %goto-if-> (x y label)
  (%lda x) (%cmp y) (%bmi label))
(defun %goto-if-< (x y label)
  (%lda x) (%cmp y) (%bpl label))
(defun %goto-if-<= (x y label)
  (%lda x) (%cmp y) (%bpl label)  (%beq label))
(defun %goto-if-not (x label)
  (%lda x) (%beq label))

(defun %inc (x)
  (declare (list x))
  (%lda x) (asm :inc :accumulator) (%sta x))

(defun %dec (x)
  (declare (list x))
  (%lda x) (asm :dec :accumulator) (%sta x))

(defun asm* (op arg)
  (fare-matcher:match arg
    ((of-type number) (asm op :immediate-w arg))
    ((list storage-class addr)
     (ecase storage-class
       (:stack (asm op :stack-indexed addr))
       (:global (asm op :absolute addr))))))

(defun %- (x y)
  (asm :sec :implied)
  (%lda x)
  (asm* :sbc y))

(defun %+ (x y)
  (asm :clc :implied)
  (%lda x)
  (asm* :adc y))
