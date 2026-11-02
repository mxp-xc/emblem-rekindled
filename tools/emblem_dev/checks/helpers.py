"""Find unreferenced private GDScript test helpers, not control-flow reachability.

Uses the existing gdtoolkit parser. Bare method values, self/member calls, literal
Callable(target, method), call/call_deferred/call_thread_safe and inherited
overrides count as references. Resource aliases from preload/load and .new() are
resolved; arbitrary runtime object flow and constructed method names are not.
For those cases place `# test-helper: dynamic-entry: <reason>` immediately above
the function. This deliberately requires a local, reviewable reason.
"""

import ast
import sys
from dataclasses import dataclass, field
from pathlib import Path

from gdtoolkit.parser import parser
from lark import Token, Tree
from lark.exceptions import UnexpectedInput

from emblem_dev.paths import GAME

# Object, SceneTree, Node, CanvasItem and Control virtual entry points used by tests.
# Other engine virtuals can use the explicit annotation rather than a prefix exemption.
OBJECT_CALLBACKS = {
    "_init",
    "_notification",
    "_get",
    "_set",
    "_get_property_list",
    "_validate_property",
    "_property_can_revert",
    "_property_get_revert",
    "_to_string",
}
TREE_CALLBACKS = {"_initialize", "_finalize", "_process", "_physics_process"}
NODE_CALLBACKS = {
    "_process",
    "_physics_process",
    "_enter_tree",
    "_exit_tree",
    "_ready",
    "_input",
    "_shortcut_input",
    "_unhandled_input",
    "_unhandled_key_input",
}
CONTROL_CALLBACKS = {
    "_gui_input",
    "_get_minimum_size",
    "_has_point",
    "_make_custom_tooltip",
    "_structured_text_parser",
}
ANNOTATION = "# test-helper: dynamic-entry:"
DECLARATIONS = {
    "const_assigned",
    "const_typed_assigned",
    "class_var_assigned",
    "class_var_typed_assgnd",
    "class_var_inf",
    "func_var_assigned",
    "func_var_typed_assgnd",
    "func_var_inf",
    "const_inf",
    "func_var_empty",
    "func_var_typed",
    "class_var_empty",
    "class_var_typed",
}
DYNAMIC_CALLS = {"call", "call_deferred", "call_thread_safe"}


def literal(node) -> str | None:
    if isinstance(node, Tree) and node.data in {"expr", "string_name"}:
        return literal(node.children[0]) if len(node.children) == 1 else None
    if isinstance(node, Tree) and node.data == "string":
        try:
            return ast.literal_eval(str(node.children[0]))
        except (ValueError, SyntaxError):
            return None
    return None


@dataclass
class Scope:
    path: Path
    tree: Tree
    name: str = ""
    functions: dict = field(default_factory=dict)
    aliases: dict = field(default_factory=dict)
    used: set = field(default_factory=set)
    callbacks: set = field(default_factory=lambda: set(OBJECT_CALLBACKS))


def check_helpers(game: Path) -> tuple[list[str], int]:
    game = game.resolve()
    paths = sorted((game / "tests").rglob("*.gd"))
    problems = []
    scopes = {}
    global_classes = {}
    comments = {}
    for path in paths:
        source = path.read_text()
        try:
            tree = parser.parse(source, gather_metadata=True)
            comments[path] = {
                comment.line: str(comment).strip()
                for comment in parser.parse_comments(source).children
            }
        except UnexpectedInput as error:
            problems.append(f"{path}:{error.line}: cannot parse test: {error.__class__.__name__}")
            continue

        def add_scope(tree, name="", path=path):
            scope = Scope(path, tree, name)
            scopes[(path, name)] = scope
            for child in tree.children:
                if not isinstance(child, Tree):
                    continue
                if child.data == "static_func_def":
                    child = child.children[0]
                if child.data == "class_def":
                    add_scope(child, str(child.children[0]))
                elif child.data == "func_def":
                    header = child.children[0]
                    scope.functions[str(header.children[0])] = child
                elif child.data == "classname_stmt":
                    global_classes[str(child.children[0])] = (path, name)
                elif child.data == "extends_stmt":
                    base = str(child.children[0])
                    if base == "SceneTree":
                        scope.callbacks.update(TREE_CALLBACKS)
                    if base in {"Node", "CanvasItem", "Node2D", "Node3D", "Control"}:
                        scope.callbacks.update(NODE_CALLBACKS)
                    if base in {"CanvasItem", "Node2D", "Control"}:
                        scope.callbacks.add("_draw")
                    if base == "Control":
                        scope.callbacks.update(CONTROL_CALLBACKS)

        add_scope(tree)

    def resolve(node, scope, aliases):
        if isinstance(node, Token):
            if node == "self":
                return (scope.path, scope.name)
            return aliases.get(str(node), global_classes.get(str(node)))
        if not isinstance(node, Tree):
            return None
        if node.data == "expr" and len(node.children) == 1:
            return resolve(node.children[0], scope, aliases)
        if node.data == "standalone_call" and str(node.children[0]) in {"preload", "load"}:
            resource = literal(node.children[1]) if len(node.children) == 2 else None
            if resource and resource.startswith("res://"):
                return ((game / resource.removeprefix("res://")).resolve(), "")
        if node.data == "getattr_call":
            member = node.children[0]
            if isinstance(member, Tree) and str(member.children[-1]) == "new":
                return resolve(member.children[0], scope, aliases)
        return None

    def declarations(tree):
        # Do not import nested class or function locals into the enclosing scope.
        if not isinstance(tree, Tree) or tree.data in {"class_def", "func_def", "static_func_def"}:
            return
        if tree.data in DECLARATIONS:
            yield tree
        for child in tree.children:
            yield from declarations(child)

    for scope in scopes.values():
        scope.aliases = {name: (scope.path, name) for path, name in scopes if path == scope.path}
        for declaration in declarations(scope.tree):
            scope.aliases[str(declaration.children[0])] = resolve(
                declaration.children[-1], scope, scope.aliases
            )

    def reference(target, name, owner):
        if target in scopes and owner != (target, name):
            scopes[target].used.add(name)

    def visit(node, scope, aliases, owner):
        if isinstance(node, Token):
            if node.type == "NAME" and str(node) not in aliases:
                reference((scope.path, scope.name), str(node), owner)
            return
        if not isinstance(node, Tree) or node.data in {"string", "string_name", "func_header"}:
            return
        if node.data == "lambda":
            nested_aliases = dict(aliases)
            for arguments in node.children[0].find_data("func_args"):
                for argument in arguments.children:
                    nested_aliases[str(argument.children[0])] = None
            for child in node.children[1:]:
                visit(child, scope, nested_aliases, owner)
            return
        if node.data in {"for_stmt", "for_stmt_typed"}:
            nested_aliases = {**aliases, str(node.children[0]): None}
            iterable = 2 if node.data == "for_stmt_typed" else 1
            visit(node.children[iterable], scope, aliases, owner)
            for child in node.children[iterable + 1 :]:
                visit(child, scope, nested_aliases, owner)
            return
        if node.data == "getattr":
            reference(resolve(node.children[0], scope, aliases), str(node.children[-1]), owner)
            visit(node.children[0], scope, aliases, owner)
            return
        if node.data in {"standalone_call", "getattr_call"}:
            function = node.children[0]
            name = str(function)
            target = (scope.path, scope.name)
            if isinstance(function, Tree) and function.data == "getattr":
                name = str(function.children[-1])
                target = resolve(function.children[0], scope, aliases)
            args = node.children[1:]
            if node.data == "standalone_call" and name == "Callable" and len(args) == 2:
                reference(resolve(args[0], scope, aliases), literal(args[1]), owner)
            elif name in DYNAMIC_CALLS and args:
                reference(target, literal(args[0]), owner)
        if node.data in DECLARATIONS:
            for child in node.children[1:]:
                visit(child, scope, aliases, owner)
            return
        for child in node.children:
            visit(child, scope, aliases, owner)

    inherited_cache = {}
    for key, scope in scopes.items():
        for child in scope.tree.children:
            if isinstance(child, Tree) and child.data in {"const_stmt", "class_var_stmt"}:
                visit(child, scope, scope.aliases, None)
        for name, function in scope.functions.items():
            aliases = dict(scope.aliases)
            header = function.children[0]
            for argument in header.find_data("func_args"):
                for arg in argument.children:
                    if isinstance(arg, Tree) and arg.children:
                        aliases[str(arg.children[0])] = None
            for child in function.children[1:]:
                for declaration in declarations(child):
                    aliases[str(declaration.children[0])] = resolve(
                        declaration.children[-1], scope, aliases
                    )
            for child in function.children[1:]:
                visit(child, scope, aliases, (key, name))
        # A named override is a dispatch entry, not an isolated test helper.
        for child in scope.tree.children:
            if not isinstance(child, Tree) or child.data != "extends_stmt":
                continue
            resource = literal(child.children[0])
            if resource and resource.startswith("res://"):
                base = game / resource.removeprefix("res://")
                if base not in inherited_cache:
                    inherited_cache[base] = {
                        str(node.children[0].children[0])
                        for node in parser.parse(base.read_text()).children
                        if isinstance(node, Tree) and node.data == "func_def"
                    }
                scope.used.update(inherited_cache[base])

    for scope in scopes.values():
        for name, function in scope.functions.items():
            if not name.startswith("_"):
                continue
            line = function.children[0].children[0].line
            previous = comments[scope.path].get(line - 1, "")
            if previous.startswith(ANNOTATION):
                if not previous.removeprefix(ANNOTATION).strip():
                    problems.append(f"{scope.path}:{line}: dynamic entry requires a reason: {name}")
                continue
            if name not in scope.used and name not in scope.callbacks:
                qualified = f"{scope.name}.{name}" if scope.name else name
                problems.append(
                    f"{scope.path}:{line}: unreferenced private test helper {qualified}"
                )
    return problems, len(paths)


def check(game: Path = GAME) -> int:
    if not (game / "tests").is_dir():
        raise ValueError("game/tests directory does not exist")
    problems, count = check_helpers(game.resolve())
    if not count:
        problems.append(f"{game / 'tests'}: no GDScript tests found")
    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        return 1
    print(f"OK private test helper references ({count} scripts; not a reachability proof)")
    return 0
