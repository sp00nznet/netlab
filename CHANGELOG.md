# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- `projects/bw.env`: Black & White, a CMake build under `src/` (script toolset on a
  clangcl builder), retail data dirs excluded, QA through its own `tools/run_tests.cmd`.
- Scenarios on netlab (`scenarios/lib.sh`): roles are a project on a machine
  with its own settings (`--as`, `--set`); `up`, `down`, `wait_log`, `press`,
  `key`, `click`, `snap` against them. The Simpsons online match runs on it,
  psnr included, and passed (joiner behind the NAT, through the relay).
  `scenarios/two-player-lan.sh` is the template for other games (RA2).
- psnr is a project: tested and built on a `go` builder, run with `netlab run
  psnr --on <host>`. Builders can have several kinds (`node,go`).
- Remote Windows runs allow the program through the firewall.
- Bringing a window forward for a snapshot or a key never sends a keystroke:
  a stray Alt put a game in menu mode, froze it, and its online opponent saw
  "PLAYER1 IS NOT RESPONDING".
- `run` stops the old program before copying the new build (a running binary
  can't be overwritten, so a server update was silently skipped).
- The loop: `netlab play` (steps files of keys, clicks, typing, menus, pad
  presses, window and log expectations, window screenshots; `drive/play.ps1`
  on Windows, `drive/play.sh` on Linux), `netlab qa` (the project's own check
  as `QA`, `QA_SKIP` so a skip isn't a pass, `QA_STEPS`, `QA_ARTIFACTS`, a
  report per run) and `netlab check` (build, then qa).
- Linux test machines: `vm/create-linux-vm.sh` (Debian 13 + Xfce that logs
  itself on, xdotool, ImageMagick, FUSE), `KIND=linux` machines, and the
  recipes' `*_LINUX` fields. connectty's AppImage runs and passes QA there.
- `docs/qa.md`: the checks the projects already have, and how they plug in.
- `netlab`: one CLI to build, run, screenshot, stop and ship any project from
  its recipe (`projects/`), plus `bench`, `times`, `status` and `log`.
- `farm/build.sh`: builds on Linux builders, sending only changed files.
  A/B against git refs and other checkouts (also in place of submodules), in
  separate slots. Clones repos without a local checkout. Places each job on
  the builder with the lowest (recorded cold build time) × (1 + load per core).
- Builders by kind (`builders/<kind>/setup.sh`, made by `builders/create.sh`):
  `clangcl` (clang-cl + lld-link + xwin, with MSVC-compatible defaults),
  `godot` (4.3, 4.6, 4.7 headless with export templates) and `node` (Node 20,
  electron-builder).
- Toolsets: `cmake`, `ps3recomp`, and `script` (the recipe's own command).
- Recipes for recompilations (Encarta, Simpsons Arcade, Force Commander, Rise
  of Legends, Burnout 3, Half-Life 2, Mario Kart DX, Let's Go Jungle,
  androidrecomp, Virtual Springfield, Catz) and for software (OpenNote,
  connectty).
- `drive/snap-window.ps1`: capture one program's window, here or on a remote
  machine's desktop session.
- A Claude skill for the farm (`.claude/skills/netlab`).
- `games/ps3recomp/`: the runtime's driving hooks and pad masks.
- `vm/`: build a Windows 10 test VM on Proxmox unattended, pass a GPU
  through, set it up through the guest agent, install AMD's driver.
- `nat/`: a home-router NAT bridge on the Proxmox host, and moving the VM
  behind it and back.
- `scenarios/simpsons-arcade/`: an online match between two instances,
  verified on a LAN and with either side behind the NAT bridge.
