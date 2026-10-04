# recomp-netlab

A build farm and test lab you drive from a terminal or an agent. It builds
your projects on Linux builders (Proxmox containers), runs them on Windows
and Linux test machines, plays them, checks them, and ships them. It started
with statically recompiled games, and handles ordinary software and games the
same way.

## The loop

```
  build ──> run ──> play ──> qa ──> ship
    ^                         │
    └──── fix, build again ───┘
```

| Step | Command | What happens |
|---|---|---|
| **build** | `netlab build <project>` | The checkout goes to the builder expected to finish first, only changed files after the first time; the build comes back to `build-farm/` |
| **run** | `netlab run <project> --on <machine>` | Started on the machine's desktop: this one, a Windows box or a Linux box over SSH |
| **play** | `netlab play <project> <steps>` | Keys, clicks, typing, menus, a game's pad, waits for a window or a log line, and screenshots of its window |
| **qa** | `netlab qa <project> --on <machine>` | Its own checks (a self-test, a conformance harness) and its steps file: PASS, FAIL or SKIP, and a report with logs and screenshots |
| **rebuild** | `netlab check <project>` | Build, then QA, in one go: the inner loop after a change |
| **ship** | `netlab ship <project> <tag>` | A GitHub draft release, itch.io, or the LAN share, per the recipe |

```sh
./netlab check opennote                  # build on the farm, then its self-test and a menu walk here
./netlab qa connectty --on linuxbox      # the AppImage on the Linux VM: window up, screenshot
./netlab ship opennote v1.4              # a draft release with the build attached
```

- **One recipe per project** says how to build, run, play, check and ship
  it: [`projects/`](projects/). Recipes hold no paths or hosts; your
  checkouts and machines live in `local/`.
- **Builders by kind:** clang-cl + xwin (MSVC-ABI Windows programs, built on
  Linux), Godot (headless export), Node (Electron, web). A builder is one
  `setup.sh` ([`builders/`](builders/)); a new stack is a new folder.
- **Test machines:** this Windows machine, a Windows VM with a real GPU
  ([vm/](vm/README.md)), and a Linux VM with a desktop that logs itself on
  ([vm/create-linux-vm.sh](vm/create-linux-vm.sh)).
- **The fastest builder that isn't busy:** every cold build's time is
  recorded per project and builder. A job goes where (its time there) ×
  (1 + load per core) is lowest. `netlab bench <project>` measures every
  builder of its kind.
- **A/B against other checkouts:** build a git ref (`--ref`), put another
  checkout in place of a dependency or a submodule, and keep each variant in
  its own slot (`--slot b`) so neither build dir is thrown away.
  ([farm/build.sh](farm/build.sh))
- **Scenarios: several programs on several machines.** Roles (a project on
  a machine, with its own settings) and steps against them: an online match
  through a server (psnr, itself a project), a LAN game between two boxes,
  with a home-router NAT on demand ([nat/](nat/)).
  ([scenarios/](scenarios/README.md), [docs/driving.md](docs/driving.md))

## Status

What has run end to end on the farm, as of 2026-10-03. Builds are from
Linux builders; "ran" means on a Windows or Linux test machine.

| Project | Kind | Built | Ran / QA |
|---|---|---|---|
| Encarta 97 | recompilation, x86 | yes | boots to an article (needs encarta#3, `-Harness`) |
| Simpsons Arcade (PS3) | recompilation, x64 | yes | online match passes: host + joiner behind a NAT, through psnr's relay |
| Red Alert 2 / Yuri's Revenge | recompilation, x86 (native32) | yes, 4.5 min cold | LAN match passes: this PC hosts, the test VM joins, both in the game ([`scenarios/redalert2/lan.sh`](scenarios/redalert2/lan.sh)); its playtest suite runs on the farm build (needs pcrecomp#47) |
| OpenNote | Win32 app | yes | QA passes: its `--selftest` and a File-menu walk |
| connectty | Electron | AppImage + deb | QA passes on the Linux VM |
| goalblins | Godot 4.6 | yes | not yet |
| psnr | Go server | yes, after its tests | runs on a Linux lab host for the scenarios |
| Black & White | hand-translated recompilation, x86 | yes | QA runs its 9 tests on the Windows VM: SKIP there (no game data), 9/9 with it |
| Mario Kart DX, Let's Go Jungle, HL2 (Xbox), Burnout 3, Force Commander, Rise of Legends, androidrecomp, Virtual Springfield, Catz | recompilations | yes | not yet |

Fixes the farm needed are upstream or open: xboxrecomp#165, pcrecomp#40,
pcrecomp#47, encarta#3, and a local Catz branch.

Next: RA2 across the NAT and to a match's end, a Unity builder (needs a licence), checks on the builder right after the
build, and QA for the recompilations that have no gate yet ([docs/qa.md](docs/qa.md)).

## Play and QA

A steps file is one step per line, the same on Windows (`drive/play.ps1`)
and Linux (`drive/play.sh`):

```
expect-window OpenNote 30     # fail unless its window is up within 30 s
key alt+f                     # menus by keyboard; also ctrl+n, enter, esc, down, f5, ...
click 410 62                  # inside the window
type hello                    # careful on a machine someone uses
pad 0x4000                    # a game's pad mailbox (the machine's PAD)
expect-log ManagerGetStatus() -> ONLINE 120
wait 3
snap file-menu.png            # the program's window only, never the whole desktop
```

The first `expect` that times out fails the run, after a screenshot of that
moment. `netlab qa` runs the recipe's `QA` command first (exit code decides;
`QA_SKIP` is a regex for a harness's way of saying it skipped something, which
is not a pass), then plays `QA_STEPS` against the running program, then
collects `QA_ARTIFACTS`. Reports go to `local/qa/<project>/<time>/`.
[docs/qa.md](docs/qa.md) lists the harnesses your projects already have and
how each one plugs in.

## Example: Encarta 97, from an agent

[encarta](https://github.com/sp00nznet/encarta) is a static recompilation:
40 MB of lifted C plus a harness, built for 32-bit Windows. Its recipe,
[`projects/encarta.env`](projects/encarta.env):

```sh
REPO=https://github.com/sp00nznet/encarta
TOOLSET=cmake                      # CMake + clang-cl on a clangcl builder
BUILD_ARGS="-DXWIN_ARCH=x86"
TARGET=recomp_enc97_run
ARTIFACTS=build/tools/recomp/recomp_enc97_run.exe
EXE=recomp_enc97_run.exe
RUN='powershell -NoProfile -ExecutionPolicy Bypass -File tools\localcontent\run-encarta.ps1 -Content $ENCARTA_CONTENT ${ENCARTA_APP:+-AppDir $ENCARTA_APP} -Harness $EXE -Hold'
SHIP=lan                           # built from a retail product: stays on the LAN
```

1. **Build.** `./netlab build encarta` sends the checkout (only files changed
   since last time), builds it on the clangcl builder expected to finish
   first, and puts `recomp_enc97_run.exe` in the checkout's `build-farm/`.
2. **Run.** `./netlab run encarta` writes a `run.cmd` next to the build and
   starts it in the checkout. `$ENCARTA_CONTENT` comes from the machine's file,
   `local/machines/local.env`. With `--on testbox`, the build and a `run.cmd`
   are copied to the test box and started in its desktop session.
3. **Play and check.** `./netlab snap encarta enc.png` captures only
   Encarta's window, never the rest of the desktop. `./netlab qa encarta`
   starts it, plays [`projects/encarta.qa`](projects/encarta.qa) (the
   article loads, then Find opens) and stops it, with a report of what it saw.
4. **Ship.** `./netlab ship encarta v0.4` copies the build to the share's
   `releases/encarta/v0.4/`. A project with `SHIP=github` gets a draft
   GitHub release instead, and `SHIP=itch` goes through butler.

## Recipes

A recipe is a shell file, `projects/<name>.env`. A project you don't publish
goes in `local/projects/<name>.env` instead, which wins over `projects/`.

| Field | What |
|---|---|
| `REPO` | Its git URL. Without a local checkout, the builder clones it |
| `TOOLSET` | `cmake` (clang-cl), `ps3recomp`, or `script` |
| `BUILDS_ON` | The builder kind, for `script` (`godot`, `node`, ...) |
| `BUILD` | The build command, for `script`, run in the project on the builder |
| `BUILD_ARGS`, `TARGET` | Extra CMake arguments; one CMake target |
| `DEPS` | Other projects it builds against: `xboxrecomp`, `pcrecomp=tools` (land as `../tools`) |
| `ARTIFACTS` | Globs for what comes back, if not the toolset's default |
| `KEEP`, `EXCLUDE` | Top-level dirs to send that are skipped by default; more paths to skip |
| `EXE`, `RUN`, `RUN_FILES`, `PROC`, `WINDOW` | What to run (a glob is fine), the command line (`$EXE` and the machine's variables expand), repo files it needs on a remote machine, the process name, its window title |
| `QA`, `QA_STEPS`, `QA_SKIP`, `QA_ARTIFACTS` | A check command (exit code decides), a steps file to play, the regex that means "skipped", and files to keep |
| `EXE_LINUX`, `RUN_LINUX`, `PROC_LINUX`, `QA_LINUX`, `QA_STEPS_LINUX` | The same, on a Linux machine |
| `SHIP`, `ITCH_TARGET` | `github`, `itch` (`user/game:channel`), `lan`, or `none` |

The farm never sends `.git`, build output, retail images, `node_modules`,
`.godot`, Unity's `Library` or cargo's `target`; the builder makes its own.

## Setting up

1. **Your lab:** `cp lab.env.example lab.env` (the Proxmox host, the test
   VMs), then `cp -r local.example local` and fill in `local/checkouts` (where
   each project is checked out) and `local/machines/` (where to run things:
   `KIND=local`, `remote` for Windows over SSH, `linux` for Linux over SSH).
2. **Test machines:** the Windows VM ([vm/README.md](vm/README.md)), and the
   Linux VM: `vm/create-linux-vm.sh` (Debian 13 + Xfce, logged on by itself,
   with xdotool and ImageMagick; set `LINUX_*` in `lab.env`).
3. **Builders:** `builders/create.sh <kind> <proxmox-host> <vmid> <storage>`
   makes a Debian container and runs `builders/<kind>/setup.sh` in it. List it
   in `farm/builders` (from `farm/builders.example`) as `<ssh target> <kind>`.
   `SHARE=<host path>` gives it a share at `/share`, where every build is
   dropped.
4. **Agents:** the [netlab skill](.claude/skills/netlab/SKILL.md) teaches
   Claude the commands. In this repo it loads on its own; to use it from
   other projects, copy or link it into `~/.claude/skills/`.

Needs Git Bash (or any POSIX shell) with `ssh`, `scp`, `tar` and `python` on
your workstation, root SSH to the Proxmox hosts, and SSH to the builders.

## Layout

| Path | What |
|---|---|
| `netlab` | The CLI: build, run, play, snap, stop, qa, check, ship, bench, times, status, log |
| `projects/` | Recipes (`local/projects/` for your private ones) |
| `farm/` | `build.sh` (sync, place, build, collect) and the builder list |
| `toolsets/<name>/` | How a builder builds one kind of project |
| `builders/<kind>/` | What a builder of that kind has (`setup.sh`); `create.sh` makes one |
| `drive/` | The play runners: `play.ps1` (Windows), `play.sh` (Linux) |
| `scenarios/` | Several programs on several machines together (`lib.sh`): online matches, LAN games, a client and its server |
| `games/<runtime>/` | One runtime's input and log hooks (ps3recomp's pad masks) |
| `vm/`, `nat/` | The test VMs, the NAT bridge |
| `local.example/` | What `local/` holds; `local/` itself is git-ignored |
| `docs/` | How driving works; what went wrong building this, and the fixes |

## License

MIT. See [LICENSE](LICENSE). The lab contains no game code or data; you
bring your own builds and games.
