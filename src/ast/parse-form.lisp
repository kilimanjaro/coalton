(in-package #:coalton-impl/ast)

(defun parse-form (expr sr package)
  "Parse the value form FORM into a NODE structure. This also performs macro-expansion.

This does not attempt to do any sort of analysis whatsoever. It is suitable for parsing expressions irrespective of environment."
  (declare (type shadow-realm sr)
	   (values node &optional)
	   (type package package))
  (cond
    ((atom expr)
     (etypecase expr
       (null    (error-parsing expr "NIL is not allowed!"))
       (symbol  (parse-variable expr sr))
       (literal-value
        (parse-atom expr))))
    ((alexandria:proper-list-p expr)
     (alexandria:destructuring-case expr
       ;; Abstraction
       ((coalton:fn vars subexpr)
        (parse-abstraction expr vars subexpr sr package))
       ((coalton:λ vars subexpr)
        (parse-abstraction expr vars subexpr sr package))
       ;; Let
       ((coalton:let bindings subexpr)
        (parse-let expr bindings subexpr sr package))
       ;; Lisp
       ((coalton:lisp type lisp-expr)
        (parse-lisp expr type lisp-expr sr))
       ;; Match
       ((coalton:match expr_ &rest patterns)
        (parse-match expr expr_ patterns sr package))
       ;; Seq
       ((coalton:seq &rest subnodes)
	(parse-seq expr subnodes sr package))
       ((t &rest rands)
        (parse-application expr (first expr) rands sr package))))
    (t (error-parsing expr "The expression is not a valid value expression."))))

(defun invert-alist (alist)
  (loop :for (key . value) :in alist
	:collect (cons value key)))

(defun lookup-or-key (sr key)
  (declare (type shadow-realm sr)
	   (type symbol key))
  (or (shadow-realm-lookup sr key)
      key))

(defun parse-variable (var sr)
  (declare (type symbol var)
	   (type shadow-realm sr)
	   (values node-variable))
  (node-variable var (lookup-or-key sr var)))

(defun make-local-vars (vars package)
  (declare (type symbol-list vars)
	   (type package package))
  (loop :for var :in vars
	:collect
	(cons
	 var
	 (alexandria:ensure-symbol (gensym (concatenate 'string (symbol-name var) "-")) package))))

(defun parse-abstraction (unparsed vars subexpr sr package)
  (declare (type t unparsed)
	   (type symbol-list vars)
	   (type t subexpr)
	   (type shadow-realm sr)
	   (type package package))
  (let* ((binding-local-names (make-local-vars vars package))
	 (new-sr (shadow-realm-push-frame sr binding-local-names)))
    (node-abstraction
     unparsed
     (mapcar #'cdr binding-local-names)
     (parse-form subexpr new-sr package)
     (invert-alist binding-local-names))))

(defun parse-let (unparsed bindings subexpr sr package)
  (declare (type t unparsed)
	   (type list bindings)
	   (type t subexpr)
	   (type shadow-realm sr)
	   (type package package)
	   (values node-let))
  (let* ((binding-names (mapcar #'car bindings))
	 (binding-local-names (make-local-vars binding-names package))
	 (new-sr (shadow-realm-push-frame sr binding-local-names)))

    (node-let
     unparsed
     (loop :for (bind-var bind-val) :in bindings
           :collect (cons
		     (lookup-or-key new-sr bind-var)
		     (parse-form bind-val new-sr package)))
     (parse-form subexpr new-sr package)
     (invert-alist binding-local-names))))

(defun rewrite-symbols (val sr)
  (declare (type shadow-realm sr))
  (cond
    ((null val)
     nil)

    ((listp val)
     (mapcar
      (lambda (val)
	(rewrite-symbols val sr))
      val))

    ((symbolp val)
     (progn
       (lookup-or-key sr val)))

    ((typep val 'literal-value)
     val)

    (t (coalton-impl::coalton-bug "Invalid structure in lisp node ~A~%" val))))

(defun parse-lisp (unparsed type lisp-expr sr)
  (declare (type shadow-realm sr))
  ;; Do *NOT* parse LISP-EXPR!
  (node-lisp unparsed type (rewrite-symbols lisp-expr sr)))

(defun parse-application (unparsed rator rands sr package)
  (declare (type shadow-realm sr)
	   (type package package))
  (cond
    ((and (symbolp rator) (macro-function rator))
     (let ((expansion (funcall (macro-function rator) (cons rator rands) nil)))
       (parse-form expansion sr package)))
    (t
     (node-application
      unparsed
      (parse-form rator sr package)
      (mapcar
       (lambda (rand)
	 (parse-form rand sr package))
       rands)))))

(defun parse-match-branch (branch sr package)
  (declare (type shadow-realm sr)
	   (type package package))
  (assert (= 2 (length branch))
          () "Malformed match branch ~A" branch)
  (let* ((parsed-pattern (parse-pattern (first branch)))
	 (pattern-vars (pattern-variables parsed-pattern))
	 (local-vars (make-local-vars pattern-vars package))
	 (new-sr (shadow-realm-push-frame sr local-vars))
	 (parsed-pattern (rewrite-pattern-vars parsed-pattern new-sr))
         (parsed-expr (parse-form (second branch) new-sr package)))
    (make-match-branch
     :unparsed branch
     :pattern parsed-pattern
     :subexpr parsed-expr
     :name-map (invert-alist local-vars))))

(defun parse-match (unparsed expr branches sr package)
  (declare (type shadow-realm sr)
	   (type package package))
  (let ((parsed-expr (parse-form expr sr package))
        (parsed-branches
	  (mapcar
	   (lambda (branch)
	     (parse-match-branch branch sr package))
	   branches)))
    (node-match unparsed parsed-expr parsed-branches)))

(defun parse-pattern (pattern)
  (cond
    ((typep pattern 'literal-value)
     (pattern-literal (parse-atom pattern)))
    ((and (symbolp pattern)
          (eql 'coalton:_ pattern))
     (pattern-wildcard))
    ((symbolp pattern)
     (pattern-var pattern))
    ((listp pattern)
     (let ((ctor (first pattern))
           (args (rest pattern)))
       (pattern-constructor ctor (mapcar #'parse-pattern args))))))

(defun parse-atom (atom)
  (node-literal atom atom))

(defun parse-seq (expr subnodes sr package)
  (declare (type t expr)
	   (type list subnodes)
	   (type shadow-realm sr)
	   (type package package))
  (assert (< 0 (length subnodes))
	  ()  "Seq form must have at least one node")
  (node-seq
   expr
   (mapcar (lambda (node)
	     (parse-form node sr package))
	   subnodes)))