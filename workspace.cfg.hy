(setv CONFIG
  {"tool" "poly-meta"
   "namespace" "thyforce"
   "paths" {"bases" "bases" "components" "components" "projects" "projects" "tests" "tests"}
   "layout" {"theme" "loose"
             "brick-path" "{kind}/{namespace}/{name}"
             "test-path" "{tests}/{kind}/{namespace}/{name}"}
   "language" {"default" "hy"
               "adapters" {"hy" {"source-ext" ".hy"
                                    "test-ext" ".hy"
                                    "interface-file" "__init__.py"
                                    "module-file" "core.hy"
                                    "test-file" "test_core.hy"}}}
   "templates"
     {"hy"
       {"component-core" ";; {name} component implementation\n"
        "base-core" ";; {name} base implementation\n"
        "interface" "import hy\nfrom {namespace}.{import-name} import core\n\n__all__ = [\"core\"]\n"
        "test" "import hy\nfrom {namespace}.{import-name} import core\n\n\ndef test_sample():\n    assert core is not None\n"}}})
