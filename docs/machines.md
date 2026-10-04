# Test machines

A machine is somewhere a build runs: `netlab run`, `snap`, `play`, `qa` and
scenario roles take `--on <machine>`. Each one is a file,
`local/machines/<name>.env`, that says how to reach it and what its recipes
need on it. Without `--on`, it's `local`, this workstation.

```
  KIND=local     this Windows workstation       run.cmd next to the build, started here
  KIND=remote    Windows over SSH (PowerShell)  build copied to DIR, started by a
                                                scheduled task in the logged-on desktop
  KIND=linux     Linux over SSH                 build copied to ~/DIR, started on :0;
                                                the recipe's *_LINUX fields apply
```

## A machine file

```sh
# local/machines/testbox.env
KIND=remote
SSH=Admin@192.0.2.30
JUMP=root@192.0.2.10    # optional: an SSH hop, e.g. when it's behind the NAT bridge
DIR=C:/netlab           # builds go to $DIR/<project>
GAME_DATA='C:\games\yourgame'   # anything its recipes' RUN lines use
```

Everything after `DIR` is yours: a recipe's `RUN='$EXE --data $GAME_DATA'`
gets each machine's own value. A scenario role can override any of them
(`role p2 yourgame testbox PLAYER=p2`).

## The kinds of machine, and what each is good for

| Machine | Set up with | Good for |
|---|---|---|
| This workstation | nothing; `local/machines/local.env` for its variables | the fastest look at a build; your own GPU. Careful: someone uses it, so no typing into real data |
| A Windows VM with a passed-through GPU | [vm/README.md](../vm/README.md): an unattended install, SSH, the GPU and its driver, autologon | games and anything that needs a real GPU; a second player; anything you don't want touching your desktop |
| A Linux VM with a desktop | `vm/create-linux-vm.sh` (Debian 13, Xfce logged on by itself, xdotool, ImageMagick) | Linux builds with a window: AppImages, Godot Linux exports. Software rendering, no GPU |
| A Linux host without a desktop | an SSH account | servers a scenario needs (`netlab run psnr --on labserver`) |
| Any other Windows PC | OpenSSH server, a key, an account that's logged on, `vm/prepare-game-box.ps1` | real hardware |

## Windows: why a scheduled task

A program started over SSH on Windows lands in session 0, which has no
desktop: no window, no screenshot, no GPU output. So `netlab run` registers
a scheduled task for the logged-on user and starts that. The box needs:

- **an account that logs on by itself** (autologon), so there is a desktop
  after a reboot;
- **OpenSSH server** with your key, and PowerShell as its shell;
- the program let through the firewall (netlab does this per run).

For the VM, the answer file sets up autologon, `vm/first-boot.ps1` sets up
SSH, and `vm/prepare-game-box.ps1` installs the VC++ runtime and `C:\netlab`.
The two scripts work on a physical PC too; set autologon there yourself
(Sysinternals Autologon, or the registry).

## Linux: a desktop that's always there

The Linux VM logs its user on to Xfce at boot (LightDM autologon), so `:0`
exists and programs started over SSH get a window. `play.sh` drives it with
xdotool and captures windows with ImageMagick's `import`. Any Linux box with
an auto-logged-on X session and those two tools works the same way.

## Networks

```
                  LAN (vmbr0)
   ┌───────────────┬───────┴──────┬──────────────┐
 workstation   builders      Linux VM      Proxmox host
                                               │ nat/nat-up.sh
                                         NAT bridge (vmbr99)
                                               │ a home-router NAT: masquerade,
                                           Windows VM  unsolicited UDP dropped
```

The Windows VM can sit behind a NAT made on the Proxmox host
(`nat/nat-up.sh`), for testing online play the way players have it:
reached through `JUMP`, its traffic masqueraded, unsolicited UDP dropped as a
home router would. `nat/vm-to-lan.sh` and `nat/vm-to-nat.sh` move it between
the LAN (for LAN games, which find each other by broadcast) and the NAT.
`lab.env` has the bridge and addresses.

## Checking a machine

```sh
./netlab run opennote --on testbox && sleep 5 && ./netlab snap opennote t.png --on testbox && ./netlab stop opennote --on testbox
```

A PNG of the program's window means SSH, the copy, the desktop session and
the capture all work.
