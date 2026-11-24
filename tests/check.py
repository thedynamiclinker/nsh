"""Exercise the installed commands with a local backend and a real terminal."""

import os
from pathlib import Path
import pty
import select
import shutil
import signal
import subprocess
import sys
from tempfile import TemporaryDirectory
from time import monotonic


class Terminal:
    def __init__(self, argv, cwd, env):
        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.chdir(cwd)
            os.execvpe(argv[0], argv, env)
        self.output = b""

    def __enter__(self):
        return self

    def __exit__(self, exc, *_):
        if exc is not None:
            try:
                os.kill(self.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        os.close(self.fd)
        _, status = os.waitpid(self.pid, 0)
        if exc is None:
            assert status == 0, status

    def expect(self, text):
        expected = text.encode()
        deadline = monotonic() + 5
        while expected not in self.output:
            remaining = max(0, deadline - monotonic())
            assert select.select([self.fd], [], [], remaining)[0], (text, self.output)
            try:
                chunk = os.read(self.fd, 4096)
            except OSError as exc:
                raise AssertionError((text, self.output)) from exc
            assert chunk, (text, self.output)
            self.output += chunk
        before, _, self.output = self.output.partition(expected)
        return before

    def enter(self, line):
        self.send((line + "\n").encode())

    def send(self, keys):
        os.write(self.fd, keys)

    def quit(self):
        self.enter(":quit")
        # Keep the terminal open until the child has processed the input.
        while True:
            assert select.select([self.fd], [], [], 5)[0]
            try:
                if not os.read(self.fd, 4096):
                    break
            except OSError:
                break


def check(prefix, directory, environment):
    environment["PATH"] = f"{prefix}/bin:" + environment["PATH"]
    backend = directory / "backend"
    backend.write_text("""#!/bin/sh
set -eu
case "$*" in
    *'Compile the source into one complete shell script'*)
        test "$LORD_EFFORT" = xhigh && test "$LORD_PERMISSION" = text
        printf '#!/bin/sh\\necho compiled\\n' ;;
    *'correct the example'*|*'clarify the example'*)
        test "$LORD_PERMISSION" = text
        if [ "$*" = 'clarify the example' ] && ! grep -q '^salute$'; then
            printf '@ask\\nWhat should it print?\\n'
            exit
        fi
        if grep -q '^# Nahas' "$LORD_PROGRAM"; then
            printf '@code\\nprint("corrected")\\n'
        elif grep -q '^# Standard Human Nature' "$LORD_PROGRAM"; then
            printf '@code\\nsay corrected\\n'
        else
            printf '@code\\necho corrected\\n'
        fi ;;
    *'native-trouble'*)
        case "$*" in *'Record: run.'*'native-trouble'*) ;; *) exit 42 ;; esac
        printf '%s\\n' "$LORD_EFFORT $LORD_PERMISSION" ;;
    *'recover recorded input'*) cat ;;
    *'runtime report'*) printf '%s\\n' "$LORD_EFFORT $LORD_PERMISSION" ;;
    *) exit 43 ;;
esac
""")
    backend.chmod(0o700)
    environment["LORD_BACKEND"] = str(backend)

    def run(*argv, data=b"", status=0):
        result = subprocess.run(argv, input=data, capture_output=True, cwd=directory, env=environment, timeout=5)
        assert result.returncode == status, (argv, result)
        return result

    data = b"one\0two\n" * 8192
    record_file = directory / "record-id"
    result = run("lord-run", "--id-file", str(record_file), "sh", "-c", "cat; echo diagnostic >&2; exit 19", data=data, status=19)
    record_id = record_file.read_text().strip()
    assert result.stdout == data
    assert run("lord-log", "stdin", record_id).stdout == data
    run("lord-run", "true")
    assert run("lord-log", "stdout", record_id).stdout == data
    assert run("lord-log", "stderr", record_id).stdout == result.stderr == b"diagnostic\n"
    assert run("lord-log", "status", record_id).stdout == b"19\n"
    assert run("nsh", "-n", "2", "-c", 'printf "%s" "$1"', "script", "a b").stdout == b"a b"
    assert run("nhs", "-n", "2", "-c", "print(sum(range(5)))").stdout == b"10\n"
    assert run("shn", "-n", "2", "-c", "7: say verse").stdout == b"verse\n"
    (directory / "this prompt").write_text("write a prompt\n")
    source = "cat 'this prompt' @ sed 's/write a prompt/do this prompt/'"
    assert run("nsh", "-c", source).stdout == b"do this prompt\n"
    assert run("nsh", "-c", 'echo "a @ b" | tr a-z A-Z').stdout == b"A @ B\n"
    assert run("@", "base64", "decode", "@", "uppercase", data=b"aGVsbG8K").stdout == b"HELLO\n"
    native = directory / "native"
    native.write_text('#!/usr/bin/env sh\nprintf "<%s>\\n" "$@"\n')
    assert run("LD", str(native), "a b", "--").stdout == b"<a b>\n<-->\n"
    prose = directory / "prose"
    prose.write_text("#!/usr/bin/env LD\nTest the loader.\n")
    prose.chmod(0o700)
    assert run(str(prose), "runtime report").stdout == b"medium text\n"
    assert run("LD", "--effort", "4", "--permission", "read", str(prose), "runtime report").stdout == b"xhigh read\n"
    assert run("LD", "--effort", "4", "--compile", str(prose)).stdout == b"#!/bin/sh\necho compiled\n"
    args = ["nsh", "-n", "0", "--effort", "4", "--permission", "read"]
    result = run(*args, "-c", "echo once >> effects; echo native-trouble >&2; exit 7")
    assert result.stdout == b"xhigh read\n" and result.stderr == b"native-trouble\n"
    assert (directory / "effects").read_text() == "once\n"
    assert run("nsh", "-n", "1", "-c", "cat >/dev/null; : recover recorded input; exit 127", data=data).stdout == data
    failed = run("nsh", "-n", "2", "-c", "echo native-trouble >&2; exit 7", status=7)
    assert failed.stdout == b"" and failed.stderr == b"native-trouble\n"

    for name in ("nsh", "NSH", "nhs", "NHS", "shn", "SHN", "snh", "SNH", "@", "SH"):
        with Terminal([name, "-n", "1"], directory, environment) as term:
            term.expect(f"{name}[r:1:2:text]")
            for command, mode, effort in (("up", "r", 3), ("dn", "r", 2), ("c", "c", 2),
                                          ("a", "a", 2), ("l", "l", 2), ("r", "r", 2)):
                term.enter(command)
                term.expect(f"{name}[{mode}:1:{effort}:text]")
            term.quit()

    for name in ("nsh", "nhs", "shn"):
        with Terminal([name, "--permission", "read"], directory, environment) as term:
            term.expect(f"{name}[r:1:2:read]")
            term.enter("c")
            term.expect(f"{name}[c:1:2:text]")
            term.enter("correct the example")
            term.expect("Use :run")
            term.expect(f"{name}[c:1:2:text]")
            term.enter(":run")
            assert b"\r\ncorrected\r\n" in term.expect(f"{name}[c:1:2:text]")
            term.enter("a")
            term.expect(f"{name}[a:1:2:text]")
            term.enter("clarify the example")
            term.expect("What should it print?")
            term.expect(f"{name}[a:1:2:text]")
            term.enter("up")
            term.expect(f"{name}[a:1:3:text]")
            term.enter("salute")
            term.expect("Use :run")
            term.expect(f"{name}[a:1:3:text]")
            term.enter("l")
            term.expect(f"{name}[l:1:3:read]")
            term.enter(f":link linked-{name}")
            term.expect(f"{name}[l:1:3:read]")
            term.enter("r")
            term.expect(f"{name}[r:1:3:read]")
            term.enter("runtime report")
            term.expect("high read")
            term.expect(f"{name}[r:1:3:read]")
            term.quit()
        assert run(str(Path(environment["LD_BINDIR"], f"linked-{name}"))).stdout == b"corrected\n"

    provider = directory / "provider-cli"
    provider.write_text('''#!/bin/sh
set -eu
case "$*" in
    'login --device-auth')
        test -t 0 && test -t 1 && test -t 2
        printf 'Provider is waiting for input\\n' >&2
        IFS= read -r answer
        test "$answer" = continue ;;
    'login status') echo 'fixture signed in' ;;
    'auth login --fail') exit 17 ;;
    'auth login --help') echo 'fixture help' ;;
    'exec '*) echo 'codex selected' ;;
    '--print '*) echo 'claude selected' ;;
    *) exit 43 ;;
esac
''')
    provider.chmod(0o700)
    environment.update(LORD_CODEX=str(provider), LORD_CLAUDE=str(provider))
    selection = Path(environment["XDG_CONFIG_HOME"], "lord/provider")
    assert run("lord", "auth", "login", "claude", "--help").stdout == b"fixture help\n"
    assert not selection.exists()

    if shutil.which("bash") is None:
        return
    readline_env = dict(environment, TERM="xterm-256color", INPUTRC=str(directory / "inputrc"))
    readline_env.pop("NSH_SHELL")
    readline_env.pop("NO_COLOR", None)
    (directory / "inputrc").touch()
    (directory / "completion-file").touch()
    prompt = "nsh[r:1:2:text]"
    with Terminal(["nsh"], directory, readline_env) as term:
        term.expect("\x1b[1;33mTHE NEW WORLD")
        term.expect(prompt)
        term.enter("echo remember-this-line")
        assert b"\rremember-this-line\r\n" in term.expect(prompt)
        term.send(b"\x1b[A\n")
        assert b"\rremember-this-line\r\n" in term.expect(prompt)
        term.send(b"echo completion-fi\t\n")
        assert b"\rcompletion-file\r\n" in term.expect(prompt)
        term.enter(":paste")
        term.expect("... ")
        term.enter("echo abandoned")
        term.expect("... ")
        term.send(b"\x03")
        term.expect("[130]> ")
        term.enter("lord auth login codex --device-auth")
        term.expect("Provider is waiting for input")
        term.enter("continue")
        term.expect(prompt)
        term.enter(":help")
        term.expect("REPL: up, dn")
        term.expect(prompt)
        term.quit()

    assert selection.read_text() == "codex\n"
    assert run("lord", "auth", "status").stdout == b"fixture signed in\n"
    run("lord", "auth", "login", "claude", "--fail", status=17)
    assert selection.read_text() == "codex\n"
    assert "lord auth" not in Path(environment["NSH_HOME"], "history").read_text()
    del environment["LORD_BACKEND"]
    assert run("lord", "fixture request").stdout == b"codex selected\n"

    with Terminal(["nsh"], directory, dict(readline_env, NO_COLOR="1")) as term:
        assert b"\x1b[1;33m" not in term.expect(prompt)
        term.send(b"\x12remember-this\r")
        term.expect("\rremember-this-line\r\n")
        term.expect(prompt)
        term.quit()


with TemporaryDirectory(prefix="new-world-") as temporary:
    directory = Path(temporary)
    prefix = directory / "install"
    environment = dict(os.environ)
    for name, path in {
        "HOME": "home", "NSH_HOME": "shell", "NHS_HOME": "nahas", "SHN_HOME": "speech",
        "LD_BINDIR": "linked", "LORD_LOG_DIR": "log", "XDG_CONFIG_HOME": "config",
    }.items():
        environment[name] = str(directory / path)
    environment.update(LORD_RECORD="1", LORD_EFFORT="2", LORD_PERMISSION="text", LORD_RUNNER="lord",
                       NW_MODE="r", NW_NITPICK="1", NSH_SHELL="sh", NHS_PYTHON=sys.executable,
                       TERM="dumb")
    Path(environment["HOME"]).mkdir()
    subprocess.run([sys.argv[1], "-s", "install", f"PREFIX={prefix}", "DESTDIR="], env=environment, check=True)
    check(prefix, directory, environment)
    print("New World commands and REPLs OK")
