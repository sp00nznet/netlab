# recomp-netlab

A lab for testing online play of statically recompiled games across real
machines and real routers, with nobody at the controllers.

- **Drive games from outside:** press buttons, wait for the game to reach a
  state, grab what's on screen. On this machine, or on another box over SSH,
  with the same calls. ([docs/driving.md](docs/driving.md))
- **A Windows test box with a real GPU:** a Proxmox VM built unattended,
  with the card passed through, as the second player. ([vm/](vm/README.md))
- **A home router on demand:** put the test box behind a NAT that behaves
  like a home router, and bring it back. ([nat/](nat/))
- **Servers:** deploy a [psnr](https://github.com/sp00nznet/psnr) server to
  a lab host. ([servers/](servers/))
- **Recipes per runtime:** how to drive a
  [ps3recomp](https://github.com/sp00nznet/ps3recomp) title
  ([games/ps3recomp/](games/ps3recomp/README.md)), and what any other runtime
  needs to be driven the same way.
- **Scenarios:** a Simpsons Arcade online match, host or joiner behind a
  NAT, same script. ([scenarios/simpsons-arcade/](scenarios/simpsons-arcade/README.md))

## Getting started

1. `cp lab.env.example lab.env` and fill in your Proxmox host, VM and GPU.
2. Build the test box: [vm/README.md](vm/README.md).
3. Describe your instances: copy
   [`drive/inst/local.env.example`](drive/inst/local.env.example) and
   [`drive/inst/remote.env.example`](drive/inst/remote.env.example) to
   `drive/inst/a.env` and `drive/inst/b.env`.
4. Try it by hand:
   ```sh
   drive/drive.sh start b
   drive/drive.sh wait b "ManagerGetStatus()" 120
   drive/drive.sh snap b b.png
   ```
5. Run a scenario:
   ```sh
   scenarios/simpsons-arcade/match.sh a b captures/
   ```

Needs Git Bash (or any POSIX shell) with `ssh`, `scp`, `python` and `ffmpeg`
on your workstation, and root SSH to the Proxmox host.

## Layout

| Path | What |
|---|---|
| `drive/` | The driving library (`lib.sh`), its CLI (`drive.sh`), instance files |
| `games/<runtime>/` | How to launch and drive one runtime's games, locally and on the box |
| `vm/` | Build the Windows GPU test box on Proxmox |
| `nat/` | The NAT bridge, and moving the box behind it and back |
| `servers/` | Game-service servers for the lab (psnr) |
| `scenarios/` | Multi-instance test runs |
| `docs/` | How driving works; what went wrong building this, and the fixes |

## License

MIT. See [LICENSE](LICENSE). The lab contains no game code or data; you
bring your own builds and games.
