import contextlib
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

import hy  # noqa: F401 - installs Hy import hook

from thyforce.poly_meta.bricks import core as bricks
from thyforce.poly_meta.check import core as check
from thyforce.poly_meta.cli import core as cli
from thyforce.poly_meta.config import core as config
from thyforce.poly_meta.deps import core as deps
from thyforce.poly_meta.projects import core as projects
from thyforce.poly_meta.sync import core as sync
from thyforce.poly_meta.workspace import core as workspace


WORKSPACE_CONFIG = r'''
(setv CONFIG
  {"tool" "poly-meta-test"
   "namespace" "acme"
   "paths" {"bases" "bases" "components" "components" "projects" "projects" "tests" "test"}
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
       {"component-core" ";; component {name}\n(import os)\n"
        "base-core" ";; base {name}\n(require hyrule [->])\n"
        "interface" "import hy\nfrom {namespace}.{import-name} import core\n\n__all__ = [\"core\"]\n"
        "test" "import hy\nfrom {namespace}.{import-name} import core\n\n\ndef test_sample():\n    assert core is not None\n"}}})
'''


@contextlib.contextmanager
def temp_workspace(config_text=WORKSPACE_CONFIG):
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        (root / "workspace.cfg.hy").write_text(config_text, encoding="utf-8")
        yield root


class PolyMetaTests(unittest.TestCase):
    def test_workspace_root_finds_nearest_cfg_hy_from_nested_dir(self):
        with temp_workspace() as root:
            nested = root / "components" / "acme" / "demo"
            nested.mkdir(parents=True)
            self.assertEqual(config.workspace_root(nested), root)

    def test_workspace_root_prefers_current_directory_config_over_parent(self):
        with temp_workspace() as root:
            child = root / "child"
            child.mkdir()
            (child / "workspace.cfg.hy").write_text(WORKSPACE_CONFIG.replace('"acme"', '"childns"'), encoding="utf-8")
            self.assertEqual(config.workspace_root(child), child)
            self.assertEqual(config.load_config(child)["namespace"], "childns")

    def test_load_config_and_get_in_and_adapter_are_data_driven(self):
        with temp_workspace() as root:
            cfg = config.load_config(root)
            self.assertEqual(cfg["namespace"], "acme")
            self.assertEqual(config.get_in(cfg, ["language", "default"]), "hy")
            self.assertEqual(config.get_in(cfg, ["missing"], "fallback"), "fallback")
            self.assertEqual(config.adapter(cfg)["module-file"], "core.hy")

    def test_create_nested_component_from_path_like_name(self):
        with temp_workspace() as root:
            cfg = config.load_config(root)
            result = bricks.create_brick(root, cfg, "components", "poly_meta/config")
            brick_dir = root / "components" / "acme" / "poly_meta" / "config"
            self.assertEqual(result["brick"], "poly_meta/config")
            self.assertEqual(Path(result["path"]), brick_dir)
            self.assertEqual((brick_dir / "core.hy").read_text(encoding="utf-8"), ";; component poly_meta/config\n(import os)\n")
            self.assertIn("from acme.poly_meta.config import core", (brick_dir / "__init__.py").read_text(encoding="utf-8"))
            self.assertTrue((root / "test" / "components" / "acme" / "poly_meta" / "config" / "test_core.hy").exists())

    def test_create_nested_base_uses_base_template(self):
        with temp_workspace() as root:
            cfg = config.load_config(root)
            bricks.create_brick(root, cfg, "bases", "poly_meta/cli")
            core = root / "bases" / "acme" / "poly_meta" / "cli" / "core.hy"
            self.assertEqual(core.read_text(encoding="utf-8"), ";; base poly_meta/cli\n(require hyrule [->])\n")

    def test_create_brick_refuses_to_overwrite_unless_requested(self):
        with temp_workspace() as root:
            cfg = config.load_config(root)
            bricks.create_brick(root, cfg, "components", "demo")
            with self.assertRaises(FileExistsError):
                bricks.create_brick(root, cfg, "components", "demo")
            result = bricks.create_brick(root, cfg, "components", "demo", overwrite=True)
            self.assertEqual(result["brick"], "demo")

    def test_list_bricks_discovers_leaf_bricks_by_configured_module_file(self):
        with temp_workspace() as root:
            cfg = config.load_config(root)
            bricks.create_brick(root, cfg, "components", "poly_meta/config")
            bricks.create_brick(root, cfg, "components", "plain")
            names = sorted(b["name"] for b in bricks.list_bricks(root, cfg, "components"))
            self.assertEqual(names, ["plain", "poly_meta/config"])

    def test_workspace_info_reports_bases_and_components(self):
        with temp_workspace() as root:
            cfg = config.load_config(root)
            bricks.create_brick(root, cfg, "components", "poly_meta/config")
            bricks.create_brick(root, cfg, "bases", "poly_meta/cli")
            info = workspace.info(root)
            self.assertEqual(info["namespace"], "acme")
            self.assertEqual([b["name"] for b in info["bases"]], ["poly_meta/cli"])
            self.assertEqual([c["name"] for c in info["components"]], ["poly_meta/config"])

    def test_hy_import_parser_collects_import_and_require_forms(self):
        text = "(import os json)\n(require hyrule [->])\n(print 1)\n"
        self.assertEqual(deps.hy_imports(text), ["os json", "hyrule"])

    def test_dependency_report_reads_hy_source_files(self):
        with temp_workspace() as root:
            cfg = config.load_config(root)
            bricks.create_brick(root, cfg, "components", "poly_meta/config")
            report = deps.dependency_report(root)
            self.assertIn("poly_meta/config", report)
            self.assertEqual(report["poly_meta/config"], ["os"])

    def test_check_and_sync_return_data_maps(self):
        with temp_workspace() as root:
            result = check.run(root)
            self.assertTrue(result["ok"])
            self.assertEqual(result["errors"], [])
            self.assertTrue(sync.run(root)["ok"])

    def test_project_data_uses_configured_projects_path(self):
        with temp_workspace() as root:
            cfg = config.load_config(root)
            data = projects.project_data(root, cfg, "service")
            self.assertEqual(data["name"], "service")
            self.assertEqual(Path(data["root"]), root / "projects" / "service")
            self.assertEqual(data["namespace"], "acme")

    def test_cli_create_component_and_info_emit_json(self):
        with temp_workspace() as root:
            old_cwd = os.getcwd()
            try:
                os.chdir(root)
                out = io.StringIO()
                with contextlib.redirect_stdout(out):
                    cli.main(["create", "component", "poly_meta/config"])
                created = json.loads(out.getvalue())
                self.assertEqual(created["brick"], "poly_meta/config")

                out = io.StringIO()
                with contextlib.redirect_stdout(out):
                    cli.main(["info"])
                info = json.loads(out.getvalue())
                self.assertEqual(info["components"][0]["name"], "poly_meta/config")
            finally:
                os.chdir(old_cwd)


if __name__ == "__main__":
    unittest.main()
