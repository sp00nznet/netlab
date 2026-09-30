# Driving a ps3recomp title

[ps3recomp](https://github.com/sp00nznet/ps3recomp) runtimes already have
the three hooks `drive/` needs (see [docs/driving.md](../../docs/driving.md)).
They're all set through environment variables. The launchers here set them
for you.

| Hook | Variable | What it does |
|---|---|---|
| Input | `PAD_FILE=<path>` | Each pad poll, a button mask in the file is pressed and the file emptied. `0x4000` presses CROSS for 40 polls; `0x0040 10` presses DOWN for 10. |
| State | stdout/stderr | The runtime logs what the title does (`[sceNpMatching2] created room …`, `[cellPad] PAD_FILE press …`). Redirect it to a file and wait on lines. |
| Frames | `LD_FRAME_DUMP=<dir>`, `LD_FRAME_DUMP_EVERY=60` | Every 60th presented frame goes to `<dir>/frame_NNNNNN.ppm`. |

Other settings that matter when driving:

| Variable | Why |
|---|---|
| `PS3_VERBOSE=0` | Required. With stderr redirected, the runtime otherwise logs every wait, and a game in play drops to about 1 fps. |
| `RSX_LIVE_DRAW=1` | The D3D12 renderer. It opens a window. |
| `--psnr host[:port]` `--username name` | Online play through a [psnr](https://github.com/sp00nznet/psnr) server (command-line flags, not variables). |
| `PS3_NET_P2P_PORT=n` | This instance's P2P port. Two instances on one machine need two. |
| `PS3_NET_TRACE=1` | Log every packet. Useful for debugging, but it costs frame rate. |
| `PAD_SCRIPT=` | Timed presses (`15:0x0008,30:0x4000`). For fixed sequences with no feedback; `PAD_FILE` is better for menus. |

Buttons are in [`buttons.sh`](buttons.sh), taken from `libs/input/cellPad.h`.

## On this machine

Set up an instance from
[`drive/inst/local.env.example`](../../drive/inst/local.env.example). Its
`START` runs [`run-local.sh`](run-local.sh).

## On another Windows machine

1. Make it a game box: `vm/prepare-game-box.ps1` installs OpenSSH access and
   the VC++ runtime.
2. Copy the game there (the build and its data).
3. Run [`install-remote.ps1`](install-remote.ps1) there, with the game's
   settings. It writes `C:\netlab\run-game.cmd` and the `netlab-game`
   scheduled task that `drive/lib.sh` starts.
4. Set up an instance from
   [`drive/inst/remote.env.example`](../../drive/inst/remote.env.example).

## Typical session

```sh
. games/ps3recomp/buttons.sh
drive/drive.sh start a
drive/drive.sh wait a "ManagerGetStatus() -> ONLINE" 120
drive/drive.sh press a $START "" 10
drive/drive.sh press a $DOWN 10 3
drive/drive.sh press a $CROSS "" 6
drive/drive.sh snap a now.png
```
