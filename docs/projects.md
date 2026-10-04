# Adding a project

A project is one recipe: a shell file of variables that says how to build
it, run it, check it and ship it. It holds no hosts or paths, so it can be
published with the project; your checkouts and machines stay in `local/`.

```
  projects/<name>.env          published recipes
  local/projects/<name>.env    private ones; wins over projects/
  local/checkouts              "<name> <path>": build your working tree, not the repo
  projects/<name>.qa           its steps file, if it has one
```

```
  recipe ──┬── TOOLSET / BUILDS_ON ──> which builder kind
           ├── BUILD / BUILD_ARGS ───> how the toolset builds it
           ├── DEPS ─────────────────> other projects synced next to it
           ├── ARTIFACTS ────────────> what comes back to build-farm/
           ├── RUN / EXE / WINDOW ───> how it starts, what to capture
           ├── QA / QA_STEPS ────────> how it's checked
           └── SHIP ─────────────────> where a release goes
```

## Pick a toolset

| Toolset | For | Builder | You give it |
|---|---|---|---|
| `cmake` | a CMake project that builds for Windows with MSVC | `clangcl` | `BUILD_ARGS`, `TARGET`, maybe `ARTIFACTS` |
| `script` | anything else: npm, go, godot, cargo, make, a CMake project that's not at the root | `BUILDS_ON` | `BUILD` (a command run in the project) and `ARTIFACTS` |
| `ps3recomp` | a ps3recomp game | `clangcl` | `DEPS=ps3recomp` |

`script` covers most projects. A toolset of your own is a folder in
`toolsets/` with a `build.sh` and a `builder` file naming its kind; see
[builders.md](builders.md).

## Examples, one per kind

**A Windows program in C/C++ (CMake):**

```sh
# OpenNote: a Win32 notes app
REPO=https://github.com/sp00nznet/opennote
TOOLSET=cmake
ARTIFACTS=build/bin/OpenNote.exe
EXE=OpenNote.exe
RUN='$EXE'
WINDOW=OpenNote
QA='$EXE --selftest'           # its own checks, exit 0 when all hold
QA_STEPS=projects/opennote.qa  # then its window and menus
SHIP=github
```

The `cmake` toolset configures with clang-cl for Windows, Release, Ninja,
and brings back the `.exe`, `.pdb` and `.map` files at the top of `build/`
and `bin/` unless `ARTIFACTS` says otherwise. `BUILD_ARGS="-DXWIN_ARCH=x86"`
makes a 32-bit build.

**An Electron app (Linux packages):**

```sh
REPO=https://github.com/sp00nznet/connectty
TOOLSET=script
BUILDS_ON=node
BUILD='npm ci && npm run build && npx electron-builder --linux AppImage deb --publish never'
EXCLUDE='packages/*/release packages/*/dist'
ARTIFACTS='packages/desktop/release/*.AppImage packages/desktop/release/*.deb'
EXE_LINUX='Connectty-*-linux-x86_64.AppImage'
RUN_LINUX='$EXE'
PROC_LINUX=Connectty
WINDOW=Connectty
QA_STEPS_LINUX=projects/connectty.qa
SHIP=github
```

The `*_LINUX` fields are used on a `KIND=linux` machine; the plain ones on
Windows. A project can have both.

**A Go server, tested before it's built:**

```sh
REPO=https://github.com/sp00nznet/psnr
TOOLSET=script
BUILDS_ON=go
BUILD='go test ./server/... && CGO_ENABLED=0 go build -o psnr-linux ./server'
ARTIFACTS=psnr-linux
EXE_LINUX=psnr-linux
RUN_LINUX='$EXE -v $PSNR_FLAGS'     # PSNR_FLAGS comes from the machine's file
PROC_LINUX=psnr-linux
SHIP=github
```

Tests in `BUILD` fail the build, so a build that came back has passed them.

**A Godot game:**

```sh
REPO=https://github.com/you/yourgame
TOOLSET=script
BUILDS_ON=godot
BUILD='mkdir -p build && godot-4.6 --headless --path . --import && godot-4.6 --headless --path . --export-release "Windows Desktop" build/YourGame.exe'
ARTIFACTS='build/YourGame.exe build/YourGame.pck'
EXE=YourGame.exe
RUN='$EXE'
WINDOW=YourGame
SHIP=itch
ITCH_TARGET=you/yourgame:windows
```

The export presets come from the project's `export_presets.cfg`. The
builder has `godot-4.3`, `godot-4.6`, `godot-4.7` (or whatever
`GODOT_VERSIONS` was when it was made).

**A project that builds against another:**

```sh
REPO=https://github.com/sp00nznet/redalert2-recomp
TOOLSET=cmake
DEPS=pcrecomp=tools             # the pcrecomp project, landed as ../tools
BUILD_ARGS="-DXWIN_ARCH=x86"
```

Each dep is another project (with its own recipe, if only for its `REPO`).
Your checkout of it is used if `local/checkouts` has one, else the builder
clones it. `=name` is the directory it lands as, next to the project, for a
project that expects `../tools`. `local/checkouts` can point one project's
dep at a different checkout: `redalert2-recomp:pcrecomp ~/src/pcrecomp-fix`.

## Running it

`RUN` is one command line. `$EXE` is the built file (found in the build by
the glob in `EXE`), and every variable in the machine's file expands too:

```sh
RUN='$EXE --data $GAME_DATA ${PLAYER:+--name $PLAYER}'
```

```sh
# local/machines/testbox.env
KIND=remote
SSH=Admin@192.0.2.30
GAME_DATA='C:\games\yourgame'
```

So the recipe never names a path; each machine says where its data is.
`RUN_FILES` lists files from the repo that the run needs on a remote machine
(config, scripts), copied next to the build. `PROC` is the process name
(for `stop`), `WINDOW` the title (for `snap` and window steps).

A program that only logs, with no window, is fine: leave `WINDOW` empty and
check it with `QA` or `expect-log`.

## Checking it

`QA` is your project's own test command, run on the machine against the
build (exit code decides). `QA_STEPS` is a steps file played against the
running program. `QA_SKIP` is a regex for a harness saying it skipped
something, so a skip doesn't pass. `QA_ARTIFACTS` are files to keep in the
report. [qa.md](qa.md) has the steps and examples.

## Shipping it

| `SHIP` | `netlab ship <project> <tag>` does |
|---|---|
| `github` | `gh release create <tag> --draft` on `REPO`, with the build attached. You review and publish it |
| `itch` | `butler push` to `ITCH_TARGET` with the tag as the version |
| `lan` | copies the build to the share's `releases/<project>/<tag>/`. For anything that mustn't leave your network |
| `none` | refuses (the default) |

## Before you publish a recipe

- No hosts, IPs, usernames or local paths: those go in `local/`.
- `REPO` is public, or the recipe goes in `local/projects/`.
- Builds from retail software or data are `SHIP=lan`.
