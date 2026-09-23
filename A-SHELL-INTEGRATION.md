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
| a-Shell submodule `cpython` | Source provenance for the Python runtime family | Native iOS build now consumes pinned commit `0c3aa6418f2f8d874e1be62e45226af002bbcc8d` | CPython PSF license applies; not a-Shell-authored code |
| a-Shell submodule `SwiftTerm` | Terminal integration reference | Not copied | SwiftTerm license applies if code is later imported |

The current HermesLink shell uses the upstream a-Shell `ios_system` source
framework, rather than copying a-Shell application files. This avoids claiming
that the a-Shell app delegate or command implementation is original HermesLink
implementation while making Blink's existing terminal calls reach the same iOS
command interpreter. The terminal view, gestures, keyboard handling, smart
keys, and Blink session UI remain unchanged.

The pinned `ios_system` revision is `cb41911b8cb0f699649f55b3886c045e7d78eb8c`
(a-Shell's v3.0.3 source line). Its shell parser provides pipelines (`|`,
`|&`), redirection, and command chaining (`&&`/`||`) while the existing Blink
`TermDevice` remains the terminal front end. The upstream shell also retains
its background-command dispatch table. HermesLink additionally splits only
unquoted standalone `&` operators and runs those commands on isolated
a-Shell sessions; `&&`, `&>`, `&|`, and `|&` remain untouched for the upstream
parser. This provides background execution without changing Blink's terminal
input, gesture, or Smart Keys path. Blink's `jobs`, `fg`, and `bg` commands now
track those HermesLink-created background jobs; `fg` waits for completion and
`bg` selects an already-running job. True stop-and-resume job control still
requires thread-level suspend/resume support in `ios_system`.

## HermesLink-created glue

- `hermes/overlay/python/sitecustomize.py`: keeps the runtime's pure-Python
  metadata and hashing fallbacks. Shell execution is provided by the pinned
  a-Shell CPython runtime and is not replaced by HermesLink glue.
- `hermes/build/build-native-ios.sh`: builds and registers the a-Shell CPython
  static modules.
- `hermes/build/fetch-ashell.sh`: reproducibly fetches the pinned a-Shell
  checkout and its exact `cpython`/`SwiftTerm` submodule commits over HTTPS.
- `hermes/build/package-hermesrt-linux.sh`: packages a pure-Python runtime
  archive on Linux from the pinned a-Shell CPython standard library; it does
  not compile or include native Python objects.
- `hermes/build/package-native-ios.sh`: packages the native iOS runtime using
  the pinned a-Shell CPython source and its configured static library ABI.

These six files are HermesLink glue and carry the standard cyanmint coding
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

The native build path uses the pinned a-Shell CPython checkout instead of the
stock CPython checkout. The source's configure-time ABI remains authoritative
(the current pinned checkout requires CPython 3.13), and successful macOS CI
and device verification are still required before delivery. No additional
`os.system`/`system()` bridge is linked into the native runtime; a-Shell's
CPython implementation owns that execution path.

The WASM command mapping is still only an entry point. The pinned checkout in
this workspace contains zero-length `wasmkit` placeholders, so no executable
WasmKit payload is copied or claimed as delivered. A complete WASM delivery
must add the exact upstream binary/framework inputs, checksums, and notices.
