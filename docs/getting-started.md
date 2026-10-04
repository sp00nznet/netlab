# Getting started

From "I have a Proxmox host and an agent" to a project built on the farm,
run, clicked through and checked. About an hour, most of it waiting on
`apt` and the first build.

```
  1. workstation        2. lab.env +         3. a builder        4. your project
     tools, SSH keys       local/               (LXC)               (a recipe)
         │                    │                   │                    │
         └────────────────────┴───────────────────┴────────────────────┘
                                       │
                          5. netlab build ─> 6. run ─> 7. qa
                                       │
                          8. test VMs, more builders, the agent
```

You can stop after step 7 and have something useful: builds off your
workstation, run and checked on it. Steps 8 and later add machines.

## What you need

| | Needs | Check |
|---|---|---|
| Workstation | Git Bash (or any POSIX shell), `ssh`, `scp`, `tar`, `python`, `git` | `ssh -V; python --version` |
| Proxmox | VE 8 or 9, root SSH with your key, a Debian 13 container template (fetched if missing) | `ssh root@<pve> pveversion` |
| Network | builders get DHCP on your LAN bridge, and their hostnames resolve from the workstation | `ping builder-clangcl-140` after step 3 |
| Agent (optional) | Claude Code, or anything that can run a shell | `claude --version` |

Windows is the tested workstation, because it doubles as the first test
machine (`KIND=local`). A Linux or macOS workstation can build and run on
remote machines, but not run things on itself yet.

## 1. The workstation

```sh
git clone https://github.com/sp00nznet/netlab
cd netlab
ssh-copy-id root@192.0.2.10        # each Proxmox host, if your key isn't there yet
```

Every command from here runs from the checkout, in Git Bash.

## 2. Tell it about your lab

```sh
cp lab.env.example lab.env         # git-ignored
cp -r local.example local          # git-ignored
cp farm/builders.example farm/builders
```

- **`lab.env`**: your Proxmox host (`PVE_HOST`), the LAN bridge
  (`LAN_BRIDGE`, usually `vmbr0`), and, for later, the test VMs' IDs,
  storages and ISOs. For now only `PVE_HOST` and `LAN_BRIDGE` matter.
- **`local/checkouts`**: one line per project, `<name> <path>`. A project
  without a line is cloned on the builder from its recipe's `REPO`.
- **`local/machines/local.env`**: this workstation. `KIND=local` and
  whatever your recipes' `RUN` lines refer to on it.
- **`farm/builders`**: empty it for now; step 3 adds a line.

None of these are tracked. Keep hosts, paths and names in them, not in
`projects/` or anywhere else in git.

## 3. A builder

A builder is a Debian container with one toolchain. Pick the kind your
first project needs:

| Kind | Builds | Setup takes |
|---|---|---|
| `clangcl` | C/C++ for Windows (MSVC ABI) with CMake: clang-cl, lld, the MSVC CRT and Windows SDK through xwin | ~10 min, 3 GB |
| `node` | Electron and web apps; Linux AppImage and deb | ~3 min |
| `go` | Go programs | ~2 min |
| `godot` | Godot 4 projects, headless export to Windows and Linux | ~5 min |

```sh
builders/create.sh clangcl root@192.0.2.10 140 local-zfs 16 32768
#                  kind    proxmox host    vmid storage cores RAM(MB)
```

It makes the container, starts it, runs `builders/clangcl/setup.sh` in it,
and prints its address. Then:

```sh
echo "root@builder-clangcl-140 clangcl" >> farm/builders
ssh root@builder-clangcl-140 true          # accept its host key once
./netlab status                            # the builder, its load and cores
```

If the name doesn't resolve, use the address it printed, or add it to your
router's DNS. One container can have several kinds (`node,go`): run both
setups in it and list both on its line.

Want every build kept somewhere central? `SHARE=/tank/drops builders/create.sh
...` mounts a host directory at `/share`, and each build is dropped there too.
See [builders.md](builders.md).

## 4. Your project

`./netlab projects` lists the recipes. Yours probably isn't there, so write
one: `local/projects/<name>.env` for something you won't publish, or
`projects/<name>.env` for something you will. The smallest ones:

```sh
# A CMake project for Windows, on clangcl
REPO=https://github.com/you/yourapp
TOOLSET=cmake
EXE=yourapp.exe
RUN='$EXE'
WINDOW=YourApp
```

```sh
# Anything with a build command, on any builder kind
REPO=https://github.com/you/yourtool
TOOLSET=script
BUILDS_ON=go
BUILD='go test ./... && go build -o yourtool-linux .'
ARTIFACTS=yourtool-linux
EXE_LINUX=yourtool-linux
RUN_LINUX='$EXE --version'
```

Point `local/checkouts` at your checkout so your uncommitted changes are what
gets built. [projects.md](projects.md) has one for each kind, and every field.

## 5. Build

```sh
./netlab build yourapp
```

It prints each candidate builder with its score, the one it picked, how much
it sent, and `build wall <s>`. The build lands in
`<checkout>/build-farm/`. The first build sends everything and builds cold;
after that, only changed files go over and the build is incremental.

When it fails: `./netlab log yourapp` shows the newest log's key lines; the
full one is in `farm/logs/`. Read the first `error:`, not the last line.

## 6. Run and look

```sh
./netlab run yourapp               # on this workstation
./netlab snap yourapp shot.png     # its window only, never the desktop
./netlab stop yourapp
```

`run` writes a `run.cmd` next to the build and starts it. `snap` finds the
window by `WINDOW` and captures just that.

## 7. QA

Add what your project already has for testing, and a steps file:

```sh
QA='$EXE --selftest'            # any command; the exit code decides
QA_STEPS=projects/yourapp.qa    # then walk its window
```

```
# projects/yourapp.qa
expect-window YourApp 30
key alt+f
wait 1
snap file-menu.png
key esc
```

```sh
./netlab qa yourapp       # PASS (0), FAIL (1) or SKIP (3), and a report in local/qa/yourapp/<time>/
./netlab check yourapp    # build, then qa: the loop after each change
```

[qa.md](qa.md) has every step, and how harnesses that skip things are kept
from passing.

## 8. Grow it

In whatever order you need:

- **More builders**, of the same kind on another node, or new kinds. Jobs
  spread on their own; `./netlab bench <project>` measures each builder.
  [builders.md](builders.md)
- **Test machines**: a Windows VM with a real GPU, a Linux VM with a desktop,
  or any machine you can SSH into. Then `--on <machine>` on run, snap, qa.
  [machines.md](machines.md)
- **The agent**: let it drive the loop. [agents.md](agents.md)
- **Scenarios**: several programs on several machines, a router's NAT in
  between. [../scenarios/README.md](../scenarios/README.md)
- **Shipping**: `SHIP=github` in the recipe and `./netlab ship yourapp v1.0`
  makes a draft release with the build attached; you publish it.

## A checklist when something is off

| Symptom | Look at |
|---|---|
| `no <kind> builder reachable` | `farm/builders`: the kind on its line, the recipe's `TOOLSET`/`BUILDS_ON`, and `ssh <builder> true` |
| a builder shows `unreachable` in `status` | `ssh <builder> true` from Git Bash: key, host key, name resolution |
| the build can't find a dependency | `DEPS` in the recipe, and where it lands (`=name`) next to the project |
| `run` starts nothing on a Windows VM | it needs a logged-on desktop: autologon, and `prepare-game-box.ps1` |
| `snap` captures the wrong thing | `WINDOW` must match the title; `PROC` the process name |

More in [troubleshooting.md](troubleshooting.md).
