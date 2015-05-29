(in-package cl-dot)

(defvar *dot-path*
  #+(or win32 mswindows) "\"C:/Program Files/ATT/Graphviz/bin/dot.exe\""
  #-(or win32 mswindows) "/usr/bin/dot"
  "Path to the dot command")

;; the path to the neato executable (used for drawing undirected
;; graphs).
(defvar *neato-path*
  #+(or win32 mswindows) "\"C:/Program Files/ATT/Graphviz/bin/neato.exe\""
  #-(or win32 mswindows) "/usr/bin/neato"
  "Path to the neato command")

(eval-when (:load-toplevel :execute)
  (setf *dot-path* (find-dot))
  (setf *neato-path* (find-neato)))

;;; Classes

(defvar *id*)

(defclass id-mixin ()
  ((id :initform (incf *id*) :initarg :id :accessor id-of)))

(defclass attributes-mixin ()
  ((attributes :initform nil :initarg :attributes :accessor attributes-of)))

(defclass basic-graph (attributes-mixin)
  ((nodes :initform nil :initarg :nodes :accessor nodes-of)
   (clusters :initform '() :initarg :clusters :accessor clusters-of)))

(defclass graph (basic-graph)
  ((edges :initform nil :initarg :edges :accessor edges-of)))

(defclass cluster (id-mixin
                   basic-graph)
  ()
  (:documentation "A subgraph containing nodes and nested subgraphs
with `dot` attributes."))

(defclass node (id-mixin
                attributes-mixin)
  ()
  (:documentation "A graph node with `dot` attributes (a plist, initarg
:ATTRIBUTES) and an optional `dot` id (initarg :ID, autogenerated
by default)."))

(defclass port-mixin ()
  ((source-port :initform nil :initarg :source-port :accessor source-port-of)
   (target-port :initform nil :initarg :target-port :accessor target-port-of)))

(defclass attributed (attributes-mixin
                      port-mixin)
  ((object :initarg :object :accessor object-of))
  (:documentation "Wraps an object (initarg :OBJECT) with `dot` attribute
information (a plist, initarg :ATTRIBUTES)"))

(defmethod print-object ((object attributed) stream)
  (print-unreadable-object (object stream :type t :identity t)
    (format stream "~A" (object-of object))))

(defclass edge (attributes-mixin
                port-mixin)
  ((source :initform nil :initarg :source :accessor source-of)
   (target :initform nil :initarg :target :accessor target-of)))

;;; Protocol functions

(defgeneric graph-object-node (graph object)
  (:documentation
   "Returns a NODE instance for this object, or NIL.

In the latter case the object will not be included in the graph, but
it can still have an indirect effect via other protocol
functions (e.g. GRAPH-OBJECT-KNOWS-OF).  This function will only be
called once for each object during the generation of a graph.")
  (:method ((graph (eql 'default)) object)
    (declare (ignore graph))
    (object-node object)))

(defgeneric graph-object-edges (graph)
  (:documentation
   "Returns a sequence of edge specifications.

An edge specification is a list (FROM TO [ATTRIBUTES]), where FROM and
TO are objects of the graph and optional ATTRIBUTES is a plist of edge
attributes.")
  (:method (graph)
    (declare (ignore graph))
    '()))

(defgeneric graph-object-points-to (graph object)
  (:documentation
   "Returns a sequence of objects to which the NODE of this object
should be connected.

The edges will be directed from this object to the others.  To assign
dot attributes to the generated edges, each object can optionally be
wrapped in a instance of ATTRIBUTED.")
  (:method ((graph (eql 'default)) object)
    (declare (ignore graph))
    (object-points-to object))
  (:method (graph (object t))
    '()))

(defgeneric graph-object-pointed-to-by (graph object)
  (:documentation
   "Returns a sequence of objects to which the NODE of this object
should be connected.

The edges will be directed from the other objects to this one. To
assign dot attributes to the generated edges, each object can
optionally be wrapped in a instance of ATTRIBUTED.")
  (:method ((graph (eql 'default)) object)
    (declare (ignore graph))
    (object-pointed-to-by object))
  (:method (graph (object t))
    '()))

(defgeneric graph-object-knows-of (graph object)
  (:documentation
   "Returns a sequence of objects that this object knows should be
part of the graph, but which it has no direct connections to.")
  (:method ((graph (eql 'default)) object)
    (declare (ignore graph))
    (object-knows-of object))
  (:method (graph (object t))
    '()))

(defgeneric graph-object-contains (graph object)
  (:documentation
   "Returns a sequence of objects that the CLUSTER corresponding to
 OBJECT should contain.

If a non-empty sequence is returned, (GRAPH-OBJECT-NODE GRAPH OBJECT)
has to return a CLUSTER instance.")
  (:method (graph object)
    '()))

(defgeneric graph-object-contained-by (graph object)
  (:documentation
   "Returns an object the corresponding CLUSTER of which should
contain the NODE corresponding to OBJECT or NIL.

If a non-nil object, say CONTAINER, is returned,
(GRAPH-OBJECT-NODE GRAPH CONTAINER) has to return a CLUSTER
instance.")
  (:method (graph object)
    nil))

;;; Public interface

(defgeneric generate-graph-from-roots (graph objects &optional attributes)
  (:documentation "Constructs a GRAPH with ATTRIBUTES starting
from OBJECTS, using the GRAPH-OBJECT- protocol.")
  (:method (graph objects &optional attributes)
    (construct-graph graph objects attributes)))

(defun print-graph (graph &rest options
                    &key (stream *standard-output*) (directed t))
  "Prints a dot-format representation GRAPH to STREAM."
  (declare (ignore stream directed))
  (apply #'generate-dot graph options))

(defun dot-graph (graph outfile &key (format :ps) (directed t))
  "Renders GRAPH to OUTFILE by running the program in \*DOT-PATH* or
*NEATO-PATH* depending on the value of the DIRECTED keyword
argument.  The default is a directed graph.  The default
FORMAT is Postscript."
  (when (null format) (setf format :ps))

  (let ((dot-path (if directed *dot-path* *neato-path*))
        (format (format nil "-T~(~a~)" format))
        (dot-string (with-output-to-string (stream)
                      (print-graph graph
                                   :stream stream
                                   :directed directed))))
    (uiop:run-program (list dot-path format "-o" (namestring outfile))
                      :input (make-string-input-stream dot-string)
                      :output *standard-output*)))

;;; Internal

(defun filter-cluster-attributes (cluster)
  (setf (attributes-of cluster)
        (remove-unknown-attributes (attributes-of cluster) *cluster-attributes*))
  cluster)

(defun cluster->node (cluster)
  (let* ((attributes (attributes-of cluster))
         (shape (getf attributes :shape)))
    (change-class cluster 'node
                  :attributes (if shape
                                  attributes
                                  (list* :shape :box attributes)))))

(defun check-node-type (node expected-type &optional reason)
  (unless (typep node expected-type)
    (error "~@<Node ~A is not of type ~S~@[~A~]~@:>"
           node expected-type reason)))

;; TODO prevent subgraph cycles
(defun construct-graph (graph objects attributes)
  (let ((result (make-instance 'graph :attributes attributes))
        (handled-objects (make-hash-table))
        (*id* 0))
    (labels ((add-edge (source target attributes &optional source-port target-port)
               (let ((edge (make-instance 'edge
                                          :attributes attributes
                                          :source source
                                          :source-port source-port
                                          :target target
                                          :target-port target-port)))
                 (push edge (edges-of result))))
             (connect (node neighbor direction)
               (multiple-value-bind (neighbor found?
                                     attributes source-port target-port)
                   (get-node neighbor)
                 (when found?
                   (multiple-value-call #'add-edge
                     (ecase direction
                       (:outgoing (values node neighbor))
                       (:incoming (values neighbor node)))
                     attributes source-port target-port))))
             (get-node (object)
               (if (typep object 'attributed)
                   (multiple-value-call #'values
                     (get-node (object-of object))
                     (attributes-of object)
                     (source-port-of object)
                     (target-port-of object))
                   (gethash object handled-objects)))
             (get-attributes (object)
               (when (typep object 'attributed)
                 (attributes-of object)))
             (ensure-parent (object)
               (or (when object (handle-object object)) result))
             (handle-object (object)
               ;; TODO don't bail out early since parent - child relations may not have been set up?
               (cond
                 ((typep object 'attributed)
                  (handle-object (object-of object)))
                 ;; Object has been already been visited => skip
                 ((nth-value 1 (get-node object)) ; TODO simplify
                  (get-node object))
                 ;; Not visited => handle
                 (t
                  (let ((node (graph-object-node graph object)))
                    (setf (gethash object handled-objects) node)

                    (mapc #'handle-object (graph-object-knows-of graph object))
                    (let* ((points-to  (graph-object-points-to graph object))
                           (pointed-to (graph-object-pointed-to-by graph object))
                           (parent     (ensure-parent
                                        (graph-object-contained-by graph object)))
                           (children   (remove nil ; TODO ugly
                                               (mapcar #'handle-object
                                                       (graph-object-contains graph object)))))
                      (mapc #'handle-object points-to)
                      (mapc #'handle-object pointed-to)
                      (when node
                        ;; Add to parent cluster, if any.
                        (check-node-type parent '(or graph cluster)
                                         " but contains nodes")
                        (pushnew node (nodes-of parent))
                        ;; If NODE contains children, remove them from
                        ;; the global node list and add them to NODE.
                        (when children
                          (check-node-type node 'cluster " but contains nodes")
                          (mapc (lambda (child)
                                  (setf (nodes-of result) (remove child (nodes-of result))) ; TODO or explicit orphan list
                                  (pushnew child (nodes-of node)))
                                children))
                        ;; Add edges.
                        (map nil (lambda (to) (connect node to :outgoing))
                             points-to)
                        (map nil (lambda (from) (connect node from :incoming))
                             pointed-to)
                        node))))))
             (handle-edge (edge-spec)
               (destructuring-bind (from to &optional attributes) edge-spec
                 (handle-object from)
                 (handle-object to)
                 (add-edge (get-node from) (get-node to) attributes))))
      ;; Traverse objects starting from the roots OBJECTS.
      (map nil #'handle-object objects)
      ;; Add explicitly specified edges.
      (map nil #'handle-edge (graph-object-edges graph))

      ;; Recursively, change `cluster' instances that turned out to
      ;; contain no nodes to `node' instances since GraphViz does not
      ;; allow empty clusters.
      (labels ((remove-empty-clusters (cluster)
                 (assert (typep cluster '(or graph cluster)))
                 (assert (null (clusters-of cluster)))
                 (let ((children)
                       (nodes))
                   (mapc (lambda (child) ; TODO loop + collect?
                           (multiple-value-bind (child child-nodes)
                               (if (typep child 'cluster)
                                   (remove-empty-clusters child)
                                   (values nil (list child)))
                             (if child
                                 (push child children)
                                 (setf nodes (append nodes child-nodes)))))
                         (nodes-of cluster))
                   (setf (clusters-of cluster) children
                         (nodes-of cluster)    nodes)
                   (cond
                     ((typep cluster 'graph)
                      cluster)
                     ((or (clusters-of cluster) (nodes-of cluster))
                      (assert (typep cluster 'cluster))
                      (filter-cluster-attributes cluster))
                     (t
                      (values nil (list* (cluster->node cluster) nodes)))))))
        (remove-empty-clusters result)))))

(defun generate-dot (graph &key (stream *standard-output*) (directed t))
  (labels ((do-cluster (cluster)
             (do-graph cluster :subgraph (id-of cluster)))
           (do-graph (graph &key subgraph (node-defaults '()) (edge-defaults '()))
             (let ((remaining-nodes (copy-list (nodes-of graph)))
                   (processed-nodes '())
                   (attributes (attributes-of graph))
                   (edge-op (if directed "->" "--"))
                   (graph-type (cond
                                 (subgraph "subgraph")
                                 (directed "digraph")
                                 (t        "graph"))))
               ;; Header, attributes and node + edge defaults.
               (format stream "~a~@[ cluster_~A~] {~%" graph-type subgraph)
               (loop for (name value) on attributes by #'cddr do
                    (case name
                      (:node
                       (setf node-defaults (append node-defaults value)))
                      (:edge
                       (setf edge-defaults (append edge-defaults value)))
                      (t
                       (print-key-value stream name value
                                        (if subgraph
                                            *cluster-attributes*
                                            *graph-attributes*))
                       (format stream ";~%"))))
               ;; Default attributes.
               (print-defaults stream "node" node-defaults *node-attributes*)
               (print-defaults stream "edge" edge-defaults *edge-attributes*)
               ;; Clusters.
               (mapc (lambda (cluster)
                       (let ((nodes (do-cluster cluster)))
                         (setf remaining-nodes (set-difference
                                                remaining-nodes nodes)
                               processed-nodes (append
                                                processed-nodes nodes))))
                     (clusters-of graph))
               ;; Remaining nodes and all edges.
               (dolist (node remaining-nodes)
                 (format stream "  ~a " (textify (id-of node)))
                 (print-attributes stream (attributes-of node) *node-attributes*)
                 (format stream ";~%"))
               (unless subgraph
                 (dolist (edge (edges-of graph))
                   (print-edge stream edge edge-op)))
               ;; Footer.
               (format stream "}~%")
               ;; Return processed nodes so containing graph can skip
               ;; them.
               (append processed-nodes remaining-nodes))))
    (with-standard-io-syntax
      (let ((*standard-output* (or stream *standard-output*))
            (*print-right-margin* 65535))
        (do-graph graph)
        (values)))))

(defgeneric print-edge (stream edge edge-op))

(defmethod print-edge ((stream t) (edge edge) (edge-op t))
  (print-edge-using-nodes
   stream edge edge-op (source-of edge) (target-of edge) ))

(defgeneric print-edge-using-nodes (stream edge edge-op source target))

;; For edges between clusters and clusters/nodes, see
;; http://www.graphviz.org/content/FaqClusterEdge
(defmethod print-edge-using-nodes (stream (edge edge) edge-op source target)
  (multiple-value-bind (source-node-id source-port source-edge-attach)
      (attach-information-of edge source :source)
    (multiple-value-bind (target-node-id target-port target-edge-attach)
        (attach-information-of edge target :target)
      (format stream "  ")
      (print-edge-nodes
       stream source-node-id source-port edge-op target-node-id target-port)
      (format stream " ")
      (print-attributes stream (append (when source-edge-attach
                                         (list :ltail source-edge-attach))
                                       (when target-edge-attach
                                         (list :lhead target-edge-attach))
                                       (attributes-of edge))
                        *edge-attributes*)
      (format stream ";~%"))))

(defgeneric attach-information-of (edge node end))

(defmethod attach-information-of ((edge edge) (node node) end)
  (values (id-of node)
          (ecase end
            (:source (source-port-of edge))
            (:target (target-port-of edge)))))

(defmethod attach-information-of ((edge edge) (node cluster) end)
  (ecase end
    (:source (when (source-port-of edge) (error "TODO not supported")))
    (:target (when (target-port-of edge) (error "TODO not supported"))))
  (values (id-of (cluster-attachable-node node)) ; TODO always available?
          nil
          (format nil "cluster_~A" (id-of node))))

(defun cluster-attachable-node (cluster)
  (or (first (nodes-of cluster))
      (some #'cluster-attachable-node (clusters-of cluster))))

(defun print-edge-nodes (stream source source-port edge-op target target-port)
  (format stream "~a~@[:~a~] ~a ~a~@[:~a~]"
          (textify source) source-port
          edge-op
          (textify target) target-port))

(defun print-defaults (stream kind attributes schema)
  (when attributes
    (format stream "  ~A " kind)
    (print-attributes stream attributes schema)
    (format stream "~%")))

(defun print-attributes (stream attributes schema)
  (format stream "[")
  (loop for (name value) on attributes by #'cddr
     for prefix = "" then "," do
       (write-string prefix)
       (print-key-value stream name value schema))
  (format stream "]"))

(defun print-key-value (stream key value attributes)
  (let* ((attribute    (find-attribute key attributes))
         (foreign-name (attribute-foreign-name attribute))
         (type         (attribute-type attribute)))
    (flet ((text-value (value)
             (typecase value
               (cons
                (destructuring-bind (alignment value) value
                  (textify value :alignment alignment)))
               (t
                (textify value)))))
      (format stream "~a=~a" foreign-name
              (etypecase type
                ((member integer)
                 (unless (typep value 'integer)
                   (error "Invalid value for ~S: ~S is not an integer"
                          key value))
                 value)
                ((member boolean)
                 (if value
                     "true"
                     "false"))
                ((member label-text)
                 (typecase value
                   ((cons (eql :html))
                    (htmlify value))
                   (t
                    (text-value value))))
                ((member text)
                 (text-value value))
                ((member float)
                 (coerce value 'single-float))
                (list
                 (unless (member value type :test 'equal)
                   (error "Invalid value for ~S: ~S is not one of ~S"
                          key value type))
                 (if (symbolp value)
                     (string-downcase value)
                     value)))))))

(defun htmlify (object)
  (check-type object (cons (eql :html) (cons null)))
  (with-output-to-string (stream)
    (labels
        ((escape-string (string &optional (stream stream))
           (loop :for c :across string :do
              (case c
                (#\"
                 (write-string "&quot;" stream))
                (#\<
                 (write-string "&lt;" stream))
                (#\>
                 (write-string "&gt;" stream))
                (#\&
                 (write-string "&amp;" stream))
                (#\Newline
                 (write-string "<br/>" stream))
                (t
                 (write-char c stream)))))
         (escape-attribute (attribute)
           (list
            (first attribute)
            (with-output-to-string (stream)
              (escape-string (second attribute) stream))))
         (textify-node (node)
           (etypecase node
             (cons
              (destructuring-bind (name attributes &rest children) node
                (format stream "<~A~@[ ~{~{~A=\"~A\"~}~^ ~}~]>"
                        name (mapcar #'escape-attribute attributes))
                (mapc #'textify-node children)
                (format stream "</~A>" name)))
             (string
              (escape-string node)))))
      (write-char #\< stream)
      (mapc #'textify-node (nthcdr 2 object))
      (write-char #\> stream))))

(defun textify (object &key alignment)
  (check-type alignment (member nil :center :left :right))
  (let ((string (princ-to-string object))
        (alignment (or alignment :center)))
    (with-output-to-string (stream)
      (write-char #\" stream)
      (loop for c across string do
            ;; Note: #\\ should not be escaped to allow \n, \l, \N, etc.
            ;; to work.
            (case c
              ((#\")
               (write-char #\\ stream)
               (write-char c stream))
              (#\Newline
               (write-char #\\ stream)
               (ecase alignment
                 (:center
                  (write-char #\n stream))
                 (:left
                  (write-char #\l stream))
                 (:right
                  (write-char #\r stream))))
              (t
               (write-char c stream))))
      (write-char #\" stream))))
