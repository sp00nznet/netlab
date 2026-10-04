# Builders

A builder is an unprivileged Debian 13 LXC container on a Proxmox node,
provisioned for one or more kinds of build. Nothing runs on it between jobs:
`netlab build` SSHes in, syncs the project into a workspace, runs the
toolset's `build.sh`, and copies the results back.

```
 builders/<kind>/setup.sh    what a builder of that kind has installed (run once)
 toolsets/<name>/build.sh    how one kind of project is built on it (every job)
 toolsets/<name>/builder     which builder kind the toolset needs
 farm/builders               your builders: "<ssh target> <kind>[,<kind>...]"
 farm/times                  each cold build's time, per project and builder
```

```
  ┌─────────────── builder-clangcl-140 (LXC) ───────────────┐
  │ /opt/farm-builder/   the kind's files, from builders/   │
  │ /work/<project>/     the synced checkout, kept warm     │
  │ /work/<dep>/         its deps, next to it               │
  │ /work/slots/<s>/     an A/B slot's own workspace        │
  │ /share/              optional: drops/ and releases/     │
  └─────────────────────────────────────────────────────────┘
```

## Kinds that exist

| Kind | Has | Used by |
|---|---|---|
| `clangcl` | clang-cl, lld-link, CMake, Ninja, the MSVC CRT and Windows SDK for x86 and x64 (xwin), `/opt/clangcl.cmake` | toolsets `cmake`, `ps3recomp`; `script` recipes that run CMake themselves |
| `node` | Node 20, electron-builder's Linux needs (fuse, dpkg, rpm) | `script` with `BUILDS_ON=node` |
| `go` | Go | `script` with `BUILDS_ON=go` |
| `godot` | headless Godot editors and export templates, `godot-<major.minor>` | `script` with `BUILDS_ON=godot` |

Running the clangcl setup accepts Microsoft's CRT/SDK licence through xwin.

## Make one

```sh
builders/create.sh <kind> <proxmox host> <vmid> <storage> [cores] [mem-MB]
builders/create.sh clangcl root@192.0.2.10 140 local-zfs 16 32768
builders/create.sh node    root@192.0.2.11 143 local-lvm  8 16384
```

It picks (or downloads) a Debian 13 template, creates the container with
your Proxmox host's root keys, starts it, copies `builders/<kind>/` into it
and runs `setup.sh`. Then list it:

```sh
echo "root@builder-clangcl-140 clangcl" >> farm/builders
```

- **Several kinds in one container:** run the second kind's `setup.sh` in it
  (`pct exec <vmid> -- sh /opt/farm-builder/setup.sh` after copying the files),
  and list both: `root@builder-node-143 node,go`.
- **A share for drops:** `SHARE=/tank/netlab builders/create.sh ...`
  bind-mounts that host directory at `/share`. Every build is copied to
  `/share/drops/<project>/<job>/`, and `SHIP=lan` releases go to
  `/share/releases/`. The directory must be owned by 100000 (the
  container's root). Builders on other nodes can mount the same NFS export.
- **Sizing:** big C/C++ builds want cores and RAM (16 cores, 32-64 GB for a
  recompiled game's generated C); Node and Go are happy with 4-8 cores.
  Disk: 64 GB, mostly workspaces.
- **A fast disk matters more than you'd expect.** A ZFS pool on a spare
  SSD made the first sync and cold builds markedly quicker than a busy pool.

## Where jobs go

```
for each builder of the kind in farm/builders:
    t     = its mean cold build time of this project (farm/times)
            or, if it has none, the best any builder has, so it gets tried
    score = t × (1 + load average / cores)
lowest score wins
```

A fast builder wins unless it's busy, and a new builder gets tried as soon
as it's listed. `BUILDER=root@builder-clangcl-141 ./netlab build <p>` forces
one.

```sh
./netlab status            # each builder's load, cores and free RAM; the latest jobs
./netlab bench <project>   # a cold build on every builder of its kind, one at a time
./netlab times [<project>] # what farm/times holds
```

## A new kind

Say you want Rust programs built for Windows with cargo-xwin:

1. `builders/rust/setup.sh`: a plain `sh` script that installs what a build
   needs. It runs as root in a fresh Debian 13 container, from
   `/opt/farm-builder/`, with `pct exec`'s PATH (no `/usr/local/bin`: call
   what you install there by full path). End with a line that prints the
   versions.

   ```sh
   set -e
   apt-get update -qq
   apt-get install -y -qq curl ca-certificates git build-essential time >/dev/null
   curl -fsSL https://sh.rustup.rs | sh -s -- -y >/dev/null
   /root/.cargo/bin/cargo install cargo-xwin >/dev/null
   /root/.cargo/bin/cargo --version
   ```

2. `builders/create.sh rust <host> <vmid> <storage>`, and list it as `rust`.
3. Recipes use it with `TOOLSET=script` and `BUILDS_ON=rust`:

   ```sh
   BUILD='. ~/.cargo/env && cargo xwin build --release --target x86_64-pc-windows-msvc'
   ARTIFACTS=target/x86_64-pc-windows-msvc/release/yourtool.exe
   ```

That's enough for most stacks. A new **toolset** is only worth it when many
projects share the same build steps (as every CMake project does):
`toolsets/<name>/build.sh` runs on the builder with `$W` (the workspace),
`$GAME` (the project's directory in it), `$JOB`, and the recipe's build
variables; it must write the paths of what comes back to
`$W/.artifacts-$JOB`. `toolsets/<name>/builder` holds the kind. Copy
`toolsets/script/build.sh` to start.

## What never gets sent

`.git`, build output (`build/`, `build-*/`, `bin/`), binaries and archives (`*.exe`, `*.dll`, `*.zip`, `*.iso`, ...),
`node_modules`, `.godot`, Unity's `Library`, cargo's `target`. `KEEP` in a
recipe sends a skipped top-level dir anyway; `EXCLUDE` skips more. After the
first sync, only files changed since the last one go over; `--full` resends
everything (a file copied in with an old timestamp is missed otherwise).
