;; See http://www.graphviz.org/doc/info/attrs.html

(in-package cl-dot)

(defun find-attribute (name attributes)
  (or (find name attributes :key #'attribute-name)
      (error "Invalid attribute ~S" name)))

(defparameter *graph-attributes*
  (remove :graph *attributes* :test-not #'member :key #'attribute-allowed-in))

(defparameter *cluster-attributes*
  (remove :cluster *attributes* :test-not #'member :key #'attribute-allowed-in))

(defparameter *node-attributes*
  (remove :node *attributes* :test-not #'member :key #'attribute-allowed-in))

(defparameter *edge-attributes*
  (remove :edge *attributes* :test-not #'member :key #'attribute-allowed-in))

(defun remove-unknown-attributes (plist attributes)
  (loop :for (key value) :on plist
     :when (find key attributes :key #'attribute-name)
     :collect key :and :collect value))
