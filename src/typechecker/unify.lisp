(in-package #:coalton-impl/typechecker)

;;;
;;; Type unification
;;;

(defun unify (substs type1 type2)
  "Unify TYPE1 and TYPE2 under given substitutions, returning an updated substitution list"
  (with-type-context ("unification of types ~A and ~A" (apply-substitution substs type1) (apply-substitution substs type2))
    (let ((new-substs (mgu (apply-substitution substs type1)
                           (apply-substitution substs type2))))
      (compose-substitution-lists new-substs substs))))

(defgeneric mgu (type1 type2)
  (:documentation "Returns a SUBSTITUTION-LIST of the most general substitutions required to unify TYPE1 and TYPE2.")
  (:method ((type1 tapp) (type2 tapp))
    (let* ((s1 (mgu (tapp-from type1)
                    (tapp-from type2)))
           (s2 (mgu (apply-substitution s1 (tapp-to type1))
                    (apply-substitution s1 (tapp-to type2)))))
      (compose-substitution-lists s2 s1)))
  (:method ((type1 tvar) (type2 ty))
    (bind-variable (tvar-tyvar type1) type2))
  (:method ((type1 ty) (type2 tvar))
    (bind-variable (tvar-tyvar type2) type1))
  (:method ((type1 tcon) (type2 tcon))
    (if (equalp (tcon-tycon type1)
                (tcon-tycon type2))
        nil
        (error 'unification-error :type1 type1 :type2 type2)))
  (:method ((type1 ty) (type2 ty))
    (error 'unification-error :type1 type1 :type2 type2)))

(defun bind-variable (tyvar type)
  (cond
    ((and (tvar-p type)
          (equalp (tvar-tyvar type) tyvar))
     nil)
    ((find tyvar (type-variables type))
     (error 'infinite-type-unification-error :type type))
    ((not (equalp (kind-of tyvar)
                  (kind-of type)))
     (error 'kind-mismatch-error
            :type tyvar
            :kind (kind-of type)))
    (t (list (%make-substitution tyvar type)))))

(defgeneric match (type1 type2)
  (:documentation "Returns a SUBSTITUTION-LIST which unifies TYPE1 to TYPE2

apply s type1 == type2")
  (:method ((type1 tapp) (type2 tapp))
    (let ((s1 (match (tapp-from type1) (tapp-from type2)))
          (s2 (match (tapp-to type1) (tapp-to type2))))
      (merge-substitution-lists s1 s2)))
  (:method ((type1 tvar) (type2 ty))
    (if (equalp (kind-of (tvar-tyvar type1)) (kind-of type2))
        (list (%make-substitution (tvar-tyvar type1) type2))
        (error 'type-kind-mismatch-error :type1 type1 :type2 type2)))
  (:method ((type1 tcon) (type2 tcon))
    (if (equalp type1 type2)
        nil
        (error 'unification-error :type1 type1 :type2 type2)))
  (:method ((type1 ty) (type2 ty))
    (error 'unification-error :type1 type1 :type2 type2)))


;;;
;;; Predicate unification
;;;

(defun predicate-mgu (pred1 pred2)
  "Returns a SUBSTITUTION-LIST of the most general substitutions required to unify PRED1 and PRED2."
  (declare (type ty-predicate pred1 pred2))
  (unless (eql (ty-predicate-class pred1)
               (ty-predicate-class pred2))
    (error 'predicate-unification-error :pred1 pred1 :pred2 pred2))
  (handler-case
      (reduce #'merge-substitution-lists
              (loop :for pred-type1 :in (ty-predicate-types pred1)
                    :for pred-type2 :in (ty-predicate-types pred2)
                    :collect (mgu pred-type1 pred-type2)))
    (coalton-type-error ()
      (error 'predicate-unification-error :pred1 pred1 :pred2 pred2))))

(defun predicate-match (pred1 pred2)
  "Returns a SUBSTITUTION-LIST of the most general substitutions required to unify PRED1 to PRED2."
  (declare (type ty-predicate pred1 pred2))
  (unless (eql (ty-predicate-class pred1)
               (ty-predicate-class pred2))
    (error 'predicate-unification-error :pred1 pred1 :pred2 pred2))
  (handler-case
      (reduce #'merge-substitution-lists
              (loop :for pred-type1 :in (ty-predicate-types pred1)
                    :for pred-type2 :in (ty-predicate-types pred2)
                    :collect (match pred-type1 pred-type2)))
    (coalton-type-error ()
      (error 'predicate-unification-error :pred1 pred1 :pred2 pred2))))