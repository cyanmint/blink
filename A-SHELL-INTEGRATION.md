# a-Shell integration and provenance

HermesLink uses the a-Shell/ios_system execution model for local commands. The
integration is intentionally split into upstream material and HermesLink glue;
upstream files are not relabeled as AI-generated work.

## Pinned upstream source

- Repository: https://github.com/holzschu/a-shell
- Commit: `8f7d318839db60f78792b37a462fc4f09d0796c9`
- License: the a-Shell application repository is BSD 3-Clause; see the copied
  `THIRD_PARTY/a-Shell-LICENSE` and retain its copyright and license notices.
  The repository also contains separately licensed
  dependencies; their notices remain applicable.
- Upstream copyright: Nicolas Holzschuch / AsheKube and the copyright holders
  named by each vendored dependency.

## Imported or adopted a-Shell interfaces

| Upstream path/interface | HermesLink use | Status | Notice |
| --- | --- | --- | --- |
| `a-Shell/AppDelegate.swift` command setup and `ios_system` dispatch | Reference for command registration and shell lifecycle | Interface adopted; source not copied | BSD 3-Clause and dependency notices apply |
| `a-Shell/ExtraCommands.swift` `wasm`/`wasm3` command registration | Reference for WASM command boundary | Interface adopted; source not copied | BSD 3-Clause and dependency notices apply |
| `a-Shell/Resources/bin/python3` and `Resources/bin/python` | Reference to a-Shell's native Python command contract | Runtime not copied yet | Must be rebuilt from the pinned upstream/submodule sources before delivery |
| `a-Shell/Resources/bin/wasm`, `wasm3`, `wasmkit` | Reference to a-Shell WASM/WASI command names | Binaries not copied | Must retain their individual upstream notices |
| a-Shell submodule `cpython` | Source provenance for the Python runtime family | Source remains external during build | CPython PSF license applies; not a-Shell-authored code |
| a-Shell submodule `SwiftTerm` | Terminal integration reference | Not copied | SwiftTerm license applies if code is later imported |

The current HermesLink bridge uses the already-linked Blink `ios_system`
framework, rather than copying a-Shell application files. This avoids claiming
that the a-Shell app delegate or command implementation is original HermesLink
code while making Python shell calls reach the same iOS command interpreter.

## HermesLink-created glue

- `hermes/overlay/cpython/Modules/_hermeslink_shell.c`: static CPython module
  exposing `system()` and `executable()` through weak-linked `ios_system` APIs.
- `hermes/overlay/python/sitecustomize.py`: installs the bridge as
  `os.system` when the native module is present.
- `hermes/build/build-native-ios.sh`: compiles and registers the static module.

These three files are HermesLink glue and carry the standard cyanmint coding
agent header. They are separately listed in `AI-GENERATED-FILES.md`; the
upstream a-Shell material above is not covered by that statement.

`THIRD_PARTY/a-Shell-LICENSE` is a verbatim license notice copied from the
pinned checkout and is retained as third-party legal material, not glue code.

The command dictionaries now expose `python3` through the embedded Hermes
runtime and expose a-Shell's `wasm3` command through the main command dictionary using the existing
`shell.framework/shell` target used by Blink. `wasmkit` remains target-gated
because the pinned a-Shell project only provides it for newer iOS versions and
HermesLink does not yet carry the corresponding framework.

## Delivery boundary

This first integration step makes the Python `os.system()` path call the iOS
shell. It does not yet claim that a-Shell's Python or WasmKit binaries have
been copied into the app. A complete a-Shell Python/WASM runtime delivery must
add the exact binary/framework inputs, their checksums, and all applicable
license notices before changing this status to delivered.
