"""Exercise helper-reference checks on isolated GDScript syntax fixtures."""

import tempfile
import textwrap
import unittest
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from pathlib import Path

from emblem_dev.checks.helpers import check, check_helpers


class TestHelperReferences(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.game = Path(directory.name)
        (self.game / "tests").mkdir()

    def script(self, source, name="tests/test_case.gd"):
        path = self.game / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(textwrap.dedent(source).lstrip())
        return path

    def problems(self):
        return check_helpers(self.game)[0]

    def test_m7_missing_invocation_fails_even_with_pass_and_recursive_call(self):
        self.script("""
            extends SceneTree
            func _initialize():
                print("PASS m7 content")
            func _random_edges():
                return _random_edges()
        """)
        problems = self.problems()
        self.assertEqual(len(problems), 1)
        self.assertIn(":4: unreferenced private test helper _random_edges", problems[0])

    def test_calls_method_values_and_signal_callbacks_count(self):
        self.script("""
            extends SceneTree
            var callback = _registered
            func _initialize():
                _direct()
                self._member()
                process_frame.connect(_callback)
                var action = func(): _lambda_target()
            func _direct(): pass
            func _member(): pass
            func _callback(): pass
            func _registered(): pass
            func _lambda_target(): pass
        """)
        self.assertEqual(self.problems(), [])

    def test_comments_and_plain_strings_do_not_count(self):
        self.script('''
            extends SceneTree
            func _initialize():
                # _missing()
                print("_missing", &'_missing', """_missing()""")
            func _missing(): pass
        ''')
        self.assertEqual(len(self.problems()), 1)

    def test_literal_dynamic_calls_and_callable_registration_count(self):
        self.script("""
            extends SceneTree
            func _initialize():
                Callable(self, &"_callable")
                call_deferred("_deferred")
                self.call("_called")
                self.call_thread_safe('_thread')
            func _callable(): pass
            func _deferred(): pass
            func _called(): pass
            func _thread(): pass
        """)
        self.assertEqual(self.problems(), [])

    def test_unresolved_receivers_and_plain_string_arguments_do_not_count(self):
        self.script("""
            extends SceneTree
            func _initialize():
                var other = Object.new()
                other._missing()
                other.call_deferred("_missing")
                Callable(other, "_missing")
                print("_missing")
            func _missing(): pass
        """)
        self.assertEqual(len(self.problems()), 1)

    def test_preload_load_instance_aliases_and_static_methods_cross_scripts(self):
        self.script("""
            extends SceneTree
            const Helper = preload("res://tests/helper.gd")
            func _initialize():
                Helper._static()
                var helper = Helper.new()
                helper._instance()
                Callable(helper, "_dynamic")
                load("res://tests/helper.gd").new()._loaded()
        """)
        self.script(
            """
            extends RefCounted
            static func _static(): pass
            func _instance(): pass
            func _dynamic(): pass
            func _loaded(): pass
        """,
            "tests/helper.gd",
        )
        self.assertEqual(self.problems(), [])

    def test_same_name_in_another_script_does_not_hide_missing_reference(self):
        self.script("""
            extends SceneTree
            func _initialize(): _same()
            func _same(): pass
        """)
        self.script(
            """
            extends RefCounted
            static func _same(): pass
        """,
            "tests/unused.gd",
        )
        problems = self.problems()
        self.assertEqual(len(problems), 1)
        self.assertIn("unused.gd:2:", problems[0])

    def test_class_name_and_nested_class_receivers_are_explicit_references(self):
        self.script("""
            extends SceneTree
            class Inner:
                func _inner(): pass
            func _initialize():
                Inner.new()._inner()
                TestFixture._static()
        """)
        self.script(
            """
            class_name TestFixture
            extends RefCounted
            static func _static(): pass
        """,
            "tests/fixture.gd",
        )
        self.assertEqual(self.problems(), [])

    def test_parameters_and_local_declarations_do_not_count(self):
        self.script("""
            extends SceneTree
            func _initialize():
                var _missing: int = 0
                print(_missing)
            func run(_missing): print(_missing)
            func _missing(): pass
        """)
        self.assertEqual(len(self.problems()), 1)

    def test_lambda_parameters_and_loop_variables_do_not_count(self):
        self.script("""
            extends SceneTree
            func _initialize():
                var callback = func(_missing): print(_missing)
                for _missing in []:
                    print(_missing)
                for _missing: int in []:
                    print(_missing)
            func _missing(): pass
        """)
        self.assertEqual(len(self.problems()), 1)

    def test_nested_classes_callbacks_and_explicit_parent_override(self):
        self.script(
            """
            extends RefCounted
            func _validate(data): return data
            class Unrelated:
                func _not_an_override(): pass
        """,
            "app/base.gd",
        )
        self.script("""
            extends SceneTree
            class Fixture:
                extends "res://app/base.gd"
                func _validate(data): return super._validate(data)
                func _not_an_override(): pass
            class Input:
                extends Node
                func _input(event): pass
                func _ready(): pass
            func _initialize(): pass
            func _input(event): pass
        """)
        problems = self.problems()
        self.assertEqual(len(problems), 2)
        self.assertTrue(any("Fixture._not_an_override" in problem for problem in problems))
        self.assertTrue(any("helper _input" in problem for problem in problems))

    def test_dynamic_entry_exception_requires_a_local_reason(self):
        self.script("""
            extends SceneTree
            # test-helper: dynamic-entry: selected by the fixture's runtime method table
            func _selected(): pass
            # test-helper: dynamic-entry:
            func _unexplained(): pass
            # test-helper: dynamic-entry: applies only to the next function
            func public_entry(): pass
            func _still_missing(): pass
        """)
        problems = self.problems()
        self.assertEqual(len(problems), 2)
        self.assertTrue(any("requires a reason: _unexplained" in problem for problem in problems))
        self.assertTrue(any("helper _still_missing" in problem for problem in problems))

    def test_syntax_error_is_reported_instead_of_skipping_script(self):
        self.script("extends SceneTree\nfunc _broken(:\n")
        problems = self.problems()
        self.assertEqual(len(problems), 1)
        self.assertIn("cannot parse test", problems[0])

    def test_exception_text_inside_multiline_string_does_not_exempt_helper(self):
        self.script('''
            extends SceneTree
            var text = """
            # test-helper: dynamic-entry: fake comment inside a string"""
            func _missing(): pass
        ''')
        self.assertEqual(len(self.problems()), 1)

    def test_native_status_and_missing_test_directory(self):
        self.script("extends SceneTree\nfunc _missing(): pass\n")
        errors = StringIO()
        with redirect_stderr(errors):
            self.assertEqual(check(self.game), 1)
        self.assertIn("_missing", errors.getvalue())
        self.script("extends SceneTree\nfunc _initialize(): pass\n")
        output = StringIO()
        with redirect_stdout(output):
            self.assertEqual(check(self.game), 0)
        self.assertIn("1 scripts", output.getvalue())
        with self.assertRaisesRegex(ValueError, "game/tests directory does not exist"):
            check(self.game / "missing")

    def test_empty_test_directory_does_not_succeed(self):
        errors = StringIO()
        with redirect_stderr(errors):
            self.assertEqual(check(self.game), 1)
        self.assertIn("no GDScript tests found", errors.getvalue())


if __name__ == "__main__":
    unittest.main()
