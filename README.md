# netlab

A build farm and test lab on the Proxmox box you already have, driven from a
terminal or by an AI agent. It builds your projects on Linux containers, runs
them on Windows and Linux test machines, clicks through them, checks them,
and ships them. One recipe per project; everything else is shell and SSH.

It's for a fairly specific situation: you have a Proxmox host (or a small
cluster) with cores to spare, several projects that take minutes to build,
and you'd rather an agent build, run and look at them for you than tie up
your workstation. If you don't have idle hardware, a hosted CI is the
better deal. If you do, netlab turns it into something that builds and
tests every kind of project you work on: native Windows programs, Electron
apps, Godot games, Go servers, static recompilations of old games.

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
| **qa** | `netlab qa <project> --on <machine>` | Its own checks (a self-test, a test suite) and its steps file: PASS, FAIL or SKIP, and a report with logs and screenshots |
| **rebuild** | `netlab check <project>` | Build, then QA, in one go: the inner loop after a change |
| **ship** | `netlab ship <project> <tag>` | A GitHub draft release, itch.io, or the LAN share, per the recipe |

```sh
./netlab check opennote                  # build on the farm, then its self-test and a menu walk here
./netlab qa connectty --on linuxbox      # the AppImage on the Linux VM: window up, screenshot
./netlab ship opennote v1.4              # a draft release with the build attached
```

## What it looks like

```
  your workstation (Windows, Git Bash)                 Proxmox node(s)
 ┌──────────────────────────────────┐      SSH      ┌────────────────────────────────────┐
 │  you, or an agent (Claude Code)  │ ────────────> │  builders: Debian LXC containers   │
 │        │                         │               │   ┌─────────┐ ┌───────┐ ┌────────┐ │
 │        v                         │   checkout    │   │ clangcl │ │ godot │ │ node,go│ │
 │     ./netlab ── farm/build.sh ───┼── (changed ──>│   └─────────┘ └───────┘ └────────┘ │
 │        │         <── build ──────┼── files only) │        │ every build dropped to    │
 │        │                         │               │        v /share (optional)         │
 │        │   checkouts: local/     │               │                                    │
 │        │   machines:  local/     │               │  test machines: VMs                │
 │        │                         │   build +     │   ┌───────────────┐ ┌────────────┐ │
 │        └── run / play / qa ──────┼── run.cmd ───>│   │ Windows + GPU │ │ Linux+Xfce │ │
 │             (or right here)      │               │   └───────────────┘ └────────────┘ │
 └──────────────────────────────────┘               └────────────────────────────────────┘
```

- **Your workstation** holds the checkouts and runs `netlab`. Nothing runs
  as a service: each command is a script that SSHes out and comes back.
- **Builders** are unprivileged LXC containers, one or more per kind of
  toolchain. Windows programs are built on Linux with clang-cl and the MSVC
  SDK (xwin), so no Windows licence is spent on building.
- **Test machines** are where programs run: this workstation itself, a
  Windows VM with a real GPU passed through, a Linux VM with a desktop that
  logs itself on. Anything you can SSH into can be one.
- **`local/`** (git-ignored) holds everything specific to you: where each
  project is checked out, how to reach each machine, private recipes. The
  tracked files hold no hosts, paths or names.

## How a build is placed

```
 netlab build foo
   │
   ├─ recipe        projects/foo.env: toolset, builder kind, deps, artifacts
   ├─ candidates    farm/builders: every builder of that kind
   ├─ score each    (its last cold build time of foo) × (1 + load per core)
   │                 no time of its own yet? the best any builder has, so it gets tried
   ├─ sync          tar of files changed since the last sync to that builder
   │                 (first time: everything but .git, build output, node_modules, ...)
   ├─ build         toolsets/<toolset>/build.sh in the builder's warm workspace
   └─ collect       artifacts back to <checkout>/build-farm/; the log to farm/logs/
```

Every cold build's time is recorded per project and builder, so a job goes
where it will finish first, not just where the load is lowest. `netlab bench
<project>` builds it cold on every builder of its kind to fill in the table.
Builds keep their workspace between runs, so the second build of a big
CMake project is ninja's incremental one.

**A/B:** build a git ref (`--ref`), put another checkout in place of a
dependency or a submodule, and keep each variant in its own slot (`--slot b`)
so neither build dir is thrown away ([farm/build.sh](farm/build.sh)).

## How a run reaches a machine

```
                     local/machines/<name>.env
                               │
         ┌─────────────────────┼──────────────────────┐
     KIND=local            KIND=remote            KIND=linux
   this workstation     Windows over SSH        Linux over SSH
         │                     │                      │
  run.cmd next to the   build + run.cmd copied   build copied to ~/netlab/,
  build, started here   to C:/netlab/<project>,  started on the logged-on
                        started by a scheduled   desktop (:0), recipe's
                        task in the desktop      *_LINUX fields apply
                        session (not session 0)
```

A machine file also holds what that machine's recipes need (`GAME_DIR=...`,
a server address). The recipe's `RUN` line refers to those variables, so one
recipe runs anywhere.

## Scenarios: several machines at once

```
            ┌────────────────────────── scenario script (scenarios/lib.sh) ───────────────────┐
            │ role server psnr  labserver                                                     │
            │ role host   game  local    PLAYER=p1 SERVER=$(addr labserver)                   │
            │ role joiner game  testbox  PLAYER=p2 SERVER=$(addr labserver)                   │
            │ up server; up host; up joiner; wait_log host "room created"; press joiner ...   │
            └──────┬──────────────────────────┬─────────────────────────────┬─────────────────┘
                   v                          v                             v
             labserver (LAN)            local (LAN)              testbox, behind nat/ (a
             the server, itself          host                    home-router NAT made on the
             a netlab project                                    Proxmox host, on demand)
```

A role is a project on a machine with its own settings. Steps (`up`,
`wait_log`, `press`, `key`, `click`, `snap`, `down`) act on roles, and a
script can retry or branch on what it sees. That's how an online match
through a server, a LAN game between two boxes, or a client against its
backend gets tested with nobody at the controls.
([scenarios/](scenarios/README.md), [docs/driving.md](docs/driving.md))

## Guides

| If you want to... | Read |
|---|---|
| go from a Proxmox host and an agent to a first build and QA run | [docs/getting-started.md](docs/getting-started.md) |
| add one of your projects | [docs/projects.md](docs/projects.md) |
| add or create builders, or a new kind of toolchain | [docs/builders.md](docs/builders.md) |
| set up test machines (your workstation, a Windows VM with a GPU, a Linux VM) | [docs/machines.md](docs/machines.md), [vm/README.md](vm/README.md) |
| hand the lab to an agent | [docs/agents.md](docs/agents.md) |
| write QA steps, plug in a project's own tests | [docs/qa.md](docs/qa.md) |
| test several programs together, a NAT in between | [scenarios/README.md](scenarios/README.md), [docs/driving.md](docs/driving.md) |
| fix something that went wrong | [docs/troubleshooting.md](docs/troubleshooting.md) |

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

## Recipes

A recipe is a shell file, `projects/<name>.env`. A project you don't publish
goes in `local/projects/<name>.env` instead, which wins over `projects/`.
[docs/projects.md](docs/projects.md) walks through one for each kind.

```sh
# connectty: an Electron app, built into Linux packages on a node builder
REPO=https://github.com/sp00nznet/connectty
TOOLSET=script
BUILDS_ON=node
BUILD='npm ci && npm run build -w @connectty/desktop && cd packages/desktop && npx electron-builder --linux AppImage deb --publish never'
ARTIFACTS='packages/desktop/release/*.AppImage packages/desktop/release/*.deb'
EXE_LINUX='Connectty-*-linux-x86_64.AppImage'
RUN_LINUX='$EXE'
PROC_LINUX=Connectty
WINDOW=Connectty
QA_STEPS_LINUX=projects/connectty.qa
SHIP=github
```

| Field | What |
|---|---|
| `REPO` | Its git URL. Without a local checkout, the builder clones it |
| `TOOLSET` | `cmake` (clang-cl), `ps3recomp`, or `script` |
| `BUILDS_ON` | The builder kind, for `script` (`godot`, `node`, `go`, ...) |
| `BUILD` | The build command, for `script`, run in the project on the builder |
| `BUILD_ARGS`, `TARGET` | Extra CMake arguments; one CMake target |
| `DEPS` | Other projects it builds against: `libfoo`, `libfoo=tools` (lands as `../tools`) |
| `ARTIFACTS` | Globs for what comes back, if not the toolset's default |
| `KEEP`, `EXCLUDE` | Top-level dirs to send that are skipped by default; more paths to skip |
| `EXE`, `RUN`, `RUN_FILES`, `PROC`, `WINDOW` | What to run (a glob is fine), the command line (`$EXE` and the machine's variables expand), repo files it needs on a remote machine, the process name, its window title |
| `QA`, `QA_STEPS`, `QA_SKIP`, `QA_ARTIFACTS` | A check command (exit code decides), a steps file to play, the regex that means "skipped", and files to keep |
| `EXE_LINUX`, `RUN_LINUX`, `PROC_LINUX`, `QA_LINUX`, `QA_STEPS_LINUX` | The same, on a Linux machine |
| `SHIP`, `ITCH_TARGET` | `github`, `itch` (`user/game:channel`), `lan`, or `none` |

The farm never sends `.git`, build output, `node_modules`, `.godot`, Unity's
`Library` or cargo's `target`; the builder makes its own.

## What runs on it today

The author's lab, as of 2026-10-04: two Proxmox nodes, four builders
(two clangcl, one Godot, one Node+Go), a Windows VM with an RX 6700 and a
Linux VM.

| Project | Kind | Built | Ran / QA |
|---|---|---|---|
| OpenNote | Win32 app (C) | yes | QA passes: its `--selftest` and a File-menu walk |
| connectty | Electron | AppImage + deb | QA passes on the Linux VM |
| psnr | Go server | yes, after its tests | runs on a Linux lab host for the scenarios |
| Simpsons Arcade (PS3) | static recompilation, x64 | yes | online match passes: host + joiner behind a NAT, through psnr's relay |
| Red Alert 2 / Yuri's Revenge | static recompilation, x86 | yes, 4.5 min cold | LAN match passes: the workstation (`local`) hosts, the Windows test VM joins, both in the game ([`scenarios/redalert2/lan.sh`](scenarios/redalert2/lan.sh)) |
| Encarta 97 | static recompilation, x86 | yes | boots to an article |
| Black & White | hand-translated, x86 | yes | its 9 tests run on the Windows VM |
| Mario Kart DX, Let's Go Jungle, HL2 (Xbox), Burnout 3, Force Commander, Rise of Legends, X-Wing Alliance, Virtual Springfield, Catz | static recompilations | yes | not yet |

Next is in [ROADMAP.md](ROADMAP.md).

## Layout

| Path | What |
|---|---|
| `netlab` | The CLI: build, run, play, snap, stop, qa, check, ship, bench, times, status, log |
| `projects/` | Recipes (`local/projects/` for your private ones) |
| `farm/` | `build.sh` (sync, place, build, collect) and the builder list |
| `toolsets/<name>/` | How a builder builds one kind of project |
| `builders/<kind>/` | What a builder of that kind has (`setup.sh`); `create.sh` makes one |
| `drive/` | The play runners: `play.ps1` (Windows), `play.sh` (Linux) |
| `scenarios/` | Several programs on several machines together (`lib.sh`) |
| `games/<runtime>/` | One game runtime's input and log hooks |
| `vm/`, `nat/` | The test VMs, the NAT bridge |
| `local.example/` | What `local/` holds; `local/` itself is git-ignored |
| `docs/` | The guides |
| `.claude/skills/netlab/` | The skill that teaches an agent the commands |

## Requirements

- A workstation with Git Bash (or any POSIX shell), `ssh`, `scp`, `tar` and
  `python`. Windows is the tested one, since it doubles as a test machine;
  `KIND=local` runs are Windows-only today.
- One or more Proxmox VE 8/9 hosts with root SSH from the workstation, and
  room for containers (each builder: a few cores, 8-64 GB RAM, 64 GB disk).
- Optional: a spare GPU for the Windows test VM, a share for build drops,
  a GitHub CLI (`gh`) or `butler` for shipping.

## License

MIT. See [LICENSE](LICENSE). The lab contains no third-party code or data;
you bring your own projects, and retail-derived builds (`SHIP=lan`) never
leave your LAN.
