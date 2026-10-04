---
name: netlab
description: Build, run, play, QA and ship the user's projects through the netlab build farm (Linux builders on Proxmox; Windows and Linux test machines). Use when asked to build a project on the farm, run or test a build, drive its UI or menus, run its checks, compare builds or builders (A/B), check build times, or ship a release.
---

# netlab

`netlab` (at the root of the netlab checkout) is the whole interface.
Run it with bash from the checkout. Every project has a recipe in
`projects/<name>.env` or `local/projects/<name>.env`.

## The loop: build -> run -> play -> qa -> (fix, build again) -> ship

```sh
./netlab projects                      # what can be built, and where each checkout is
./netlab build <project>               # -> <checkout>/build-farm/
./netlab run <project> [--on <machine>]
./netlab play <project> steps.txt [--on <machine>]  # keys, clicks, menus, pad, expects, snaps
./netlab snap <project> out.png [--on <machine>]    # its window only; then look at the PNG
./netlab stop <project> [--on <machine>]
./netlab qa <project> [--on <machine>]  # its checks + QA_STEPS: PASS / FAIL / SKIP + a report
./netlab check <project> [--on <machine>]           # build, then qa
./netlab ship <project> <tag>          # per the recipe's SHIP
```

Machines are in `local/machines/` (`local` is this one; `KIND=linux` ones
are Linux desktops). A steps file is one step per line: `wait <s>`,
`key <combo>`, `type <text>`, `click <x> <y>` (inside the window),
`pad <mask> [hold]`, `expect-window <title> [s]`, `expect-log <text> [s]`,
`snap <name.png>`. Write one to walk menus or reach a state, then read the
PNGs it leaves in `local/qa/<project>/<time>/`. `docs/qa.md` lists the
checks each project already has.

- `build` prints the candidate builders and their scores, the builder it
  picked, the sync size, and `build wall <s>`. The full log is in
  `farm/logs/`; `./netlab log <project>` shows the newest one.
- A failed build exits non-zero. Read the first `error:` in the log, not the
  last line.
- `qa` exits 0 on PASS, 1 on FAIL, 3 on SKIP (a harness skipped something:
  not a pass). Read `qa.log` and the screenshots in the report, not only the
  verdict.
- `run` returns once the program has started. Wait a few seconds (or longer
  for big programs) before `snap`, and read the PNG to check what it shows.
  Always `stop` it when you're done.

## Scenarios

Several programs on several machines (an online match, a LAN game, a client
and its server) are shell scripts on `scenarios/lib.sh`: `role <name>
<project> <machine> [K=V...]`, then `up`, `wait_log`, `press`, `key`,
`click`, `snap`, `down` against roles. Run an existing one, e.g.
`scenarios/simpsons-arcade/match.sh local testbox labserver`; for a new
game, copy `scenarios/two-player-lan.sh` (see `scenarios/README.md`).

## A/B

```sh
./netlab build <project> --slot a                 # the checkout as it is
./netlab build <project> --slot b --ref <git-ref> # an older or other commit
./netlab bench <project>                           # a cold build on every builder of its kind
./netlab times [<project>]                         # recorded cold build times
```

Each slot keeps its own workspace on the builder and its own output dir
(`build-farm-<slot>/`). To build against a different checkout of a
dependency, or in place of a submodule, call `farm/build.sh` directly with
`<dir>=<name>` (see the comment at the top of `farm/build.sh`).

## Rules

- **Shipping publishes. Ask the user before `netlab ship`.** `SHIP=github`
  makes a draft release, `itch` pushes to itch.io, `lan` copies to the share.
- `SHIP=lan` projects are built from retail products. Their builds never
  leave the LAN: don't upload, attach or commit them anywhere.
- Don't `type` into a program on a machine someone uses (`local`): it may be
  their real data. Use the test VMs for steps that change things.
- `run` and `snap` act on a real desktop. `snap` captures only the project's
  window. Don't take full-desktop screenshots of the user's machine.
- Don't edit `farm/build.sh` or `netlab` while a build is running: bash
  reads scripts as it goes, so the running job breaks.
- Machines, checkouts and builders are the user's (`local/`,
  `farm/builders`). Don't add hosts, IPs or paths to tracked files.
