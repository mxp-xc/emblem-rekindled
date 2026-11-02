"""Assemble checkout-local Typer commands and handle process exit boundaries."""

import signal
import subprocess
import traceback

import typer

from emblem_dev.commands import build, check, content, qa, root, verify, workspace

app = typer.Typer(help="本 checkout 的开发工具。", no_args_is_help=True)
app.add_typer(root.app)
app.add_typer(workspace.app, name="workspace")
app.add_typer(check.app, name="check")
app.add_typer(qa.app, name="qa")
app.add_typer(build.app, name="build")
app.add_typer(verify.app, name="verify")
app.add_typer(content.app, name="import")


def main(argv: list[str] | None = None) -> int:
    """Translate terminal signals after native business finally blocks unwind."""

    def terminate(signum, _frame):
        raise SystemExit(128 + signum)

    previous = {
        signum: signal.signal(signum, terminate) for signum in (signal.SIGINT, signal.SIGTERM)
    }
    try:
        app(args=argv, prog_name="er")
        return 0
    except KeyboardInterrupt:
        return 130
    except typer.Abort:
        return 130
    except SystemExit as error:
        return error.code if isinstance(error.code, int) else 1
    except subprocess.CalledProcessError as error:
        traceback.print_exception(error)
        return error.returncode if error.returncode > 0 else 128 - error.returncode
    except (OSError, ValueError, RuntimeError) as error:
        typer.echo(f"er: {error}", err=True)
        traceback.print_exception(error)
        return 1
    finally:
        for signum, handler in previous.items():
            signal.signal(signum, handler)
