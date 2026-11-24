# New World shells

| Commands | Native execution |
| --- | --- |
| `nsh`, `NSH`, `SH` | POSIX shell, configurable with `NSH_SHELL` |
| `nhs`, `NHS` | Python, configurable with `NHS_PYTHON` |
| `shn`, `SHN`, `snh`, `SNH` | Line-oriented speech |
| `@` | Unix stream filters and semantic requests |

With a terminal and no arguments, each command opens a REPL. Use
`-c SOURCE`, a source file, or stdin for native-first execution.
`-- REQUEST` selects a semantic turn explicitly. `--check FILE` checks
native source. `--link NAME FILE` installs source with a shebang into
`LD_BINDIR` or `~/.local/bin`.

The prompt shows mode, nitpick level, effort (0–5), and permission.
Type `up` or `dn` to change effort and `c`, `a`, `r`, or `l` to change
mode. The longer controls are `:mode`, `:nitpick`, `:effort`, and
`:permission`. Use the matching flags for a single invocation.

| Mode | Behavior on a failed native statement |
| --- | --- |
| `c` | Request a correction and validate it. `:run` runs the correction. |
| `a` | Ask for meaning, then propose validated source when it is clear. |
| `r` | Send the request to the backend with the selected permission. |
| `l` | Keep the source available to install with `:link NAME`. |

Runtime is the default mode. Compile and ask use text permission. Failed
commands can produce effects before fallback receives control. On a pipe
or file, fallback receives recorded stdin followed by any remaining input.

Nitpick level `2` is native only. Level `1` allows semantic fallback on
syntax or vocabulary errors, including shell exit status 126 or 127.
Level `0` also allows fallback on runtime failure. Lowercase commands
start at level `1`, uppercase dialects at level `0`.

Use `:paste` for a block ending in a blank line. Use `:answer TEXT` if a
reply matches a REPL control. `:cancel` discards a pending question or
correction. The shell REPL keeps working directory,
variables, and functions. `ld.so COMMAND` gives a native turn the terminal
streams. Nahas uses a persistent Python namespace when Python is installed.

```sh
nsh -n 2 -c 'printf "%s\n" "$1"' program argument
nhs -c 'print(sum(range(10)))'
shn -c '1: say Good morning'
printf 'aGVsbG8=' | @ base64 decode to stdout @ uppercase
base64 < image.png | @ base64 decode to stdout @ ocr
```

A standalone `@` argument separates stages. Each completed stage supplies
its bytes to the next. `@ -- REQUEST` keeps `@` literal in one request.
NSH also accepts `cat 'my file' @ sed 's/old/new/'` in the REPL and with
`-c`. Base64 stages use native utilities. OCR uses Tesseract when available and
otherwise needs a backend that accepts the image through stdin.

## Local vocabulary

- The shell reads declarations from `$NSH_HOME/etc/nsh.bash`. Plain
  language definitions in `$NSH_HOME/etc/nshrc` go to the semantic backend.
  `NSH_HOME` defaults to `~/.nsh`.
- Nahas reads `$NHS_HOME/etc/nhsrc.py`, under
  `${XDG_CONFIG_HOME:-$HOME/.config}/nhs` by default.
- Speech reads `$SHN_HOME/etc/shnrc` as shell configuration, under
  `${XDG_CONFIG_HOME:-$HOME/.config}/shn` by default. Set `SHN_MAX_LINE`
  to change the maximum from 120 characters.
- A speech line can begin with a numeric verse. `say TEXT`, `input`, and
  `define CATEGORY/TERM` are built in. `run COMMAND WORD ...` searches
  `SHN_PATH`. The default searches `$SHN_HOME/bin`, `~/bin`, then the
  installed speech library. Add directories to bring in new vocabulary.
- Put tab-separated `alias<TAB>expansion` lines in
  `$SHN_HOME/etc/aliases`. Set `SHN_DICT_PATH` to add dictionary
  directories. The optional Sudocode port supplies `define nature/Moon`.

`make install` and `make develop` bring in LD and lord. `make uninstall`
and `make clean` apply to the shell package. Select a provider with
`LORD_BACKEND` or use one of lord's built-in adapters.
