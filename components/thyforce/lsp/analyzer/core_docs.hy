"Hy core form docs.

Hy compiler forms are not ordinary runtime Python values; many are pattern-macro
wrappers with no useful __doc__. This table is deliberately explicit: small,
versionable, and replaceable later by data generated from Hy's own metadata.
Each entry is a map {\"signature\" str \"documentation\" str}.
"

(defn core-doc [signature documentation]
  {"signature" signature "documentation" documentation})

(setv CORE-DOCS
  {"if" (core-doc "(if test true-value false-value)"
          "Evaluate TEST. If it is truthy, evaluate and return TRUE-VALUE; otherwise evaluate and return FALSE-VALUE. Use (do ...) when a branch needs multiple forms.")
   "do" (core-doc "(do body...)"
          "Evaluate BODY forms in order and return the value of the last form.")
   "setv" (core-doc "(setv target value ...)"
            "Assign values to targets. Accepts one or more TARGET VALUE pairs.")
   "setx" (core-doc "(setx target value)"
            "Assignment expression form. Assign VALUE to TARGET and return the assigned value.")
   "defn" (core-doc "(defn name [params] body...)"
            "Define a function. A string literal at the start of BODY becomes the function docstring.")
   "fn" (core-doc "(fn [params] body...)"
          "Create an anonymous function.")
   "defclass" (core-doc "(defclass name [bases...] body...)"
                "Define a Python class. A string literal at the start of BODY becomes the class docstring.")
   "defmacro" (core-doc "(defmacro name [params] body...)"
                "Define a Hy macro in the current macro scope.")
   "import" (core-doc "(import module...)"
              "Import Python modules, names, or aliases into the current namespace.")
   "require" (core-doc "(require module...)"
               "Import Hy macros so they can be used at compile time.")
   "for" (core-doc "(for [clauses] body...)"
           "Python-style for loop. The bracketed clauses have the same shape as lfor clauses. BODY forms are evaluated for side effects; the form returns None.")
   "lfor" (core-doc "(lfor clauses value)"
            "List comprehension. CLAUSES can include LVALUE ITERABLE, :async LVALUE ITERABLE, :do FORM, :setv LVALUE RVALUE, and :if CONDITION. VALUE is accumulated into a list.")
   "dfor" (core-doc "(dfor clauses key value)"
            "Dictionary comprehension. Like lfor, but each iteration evaluates KEY and VALUE and accumulates them into a dictionary.")
   "sfor" (core-doc "(sfor clauses value)"
            "Set comprehension. Like lfor, but accumulates results into a set.")
   "gfor" (core-doc "(gfor clauses value)"
            "Generator comprehension. Like lfor, but returns a generator instead of immediately building a list.")
   "when" (core-doc "(when test body...)"
            "Shorthand for (if test (do body...) None).")
   "cond" (core-doc "(cond test result ...)"
            "Shorthand for nested if forms. Tests and results are paired; returns None if no test matches unless you provide a final True fallback.")
   "while" (core-doc "(while condition body...)"
             "Loop while CONDITION is truthy. BODY forms are evaluated for side effects and the form returns None.")
   "try" (core-doc "(try body... (except ... ) (else ... ) (finally ...))"
           "Exception-handling form corresponding to Python try/except/else/finally.")
   "with" (core-doc "(with [context target ...] body...)"
            "Context-manager form corresponding to Python with. Evaluates BODY within the dynamic extent of the context managers.")
   "match" (core-doc "(match subject case...)"
             "Structural pattern matching form corresponding to Python match/case.")
   "return" (core-doc "(return value)" "Return from the nearest enclosing function.")
   "yield" (core-doc "(yield value)" "Yield a value from a generator function.")
   "await" (core-doc "(await awaitable)" "Await an awaitable object in an async context.")})
