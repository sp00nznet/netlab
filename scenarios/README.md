# Scenarios

A scenario plays several programs on several machines together: two copies
of a game in an online match, a LAN game between two boxes, a client and its
server. It's a plain shell script on [`lib.sh`](lib.sh), so menus can retry
and the script can decide what to do next from what it sees.

| Scenario | What it proves |
|---|---|
| [`simpsons-arcade/`](simpsons-arcade/README.md) | an online match through a psnr server, on a LAN or with either side behind a NAT |
| [`redalert2/lan.sh`](redalert2/lan.sh) | Red Alert 2 against itself over the LAN: lobby, join, accept, start, both in the game; pictures from the game's own frames |
| [`two-player-lan.sh`](two-player-lan.sh) | the starting point for any two-player LAN test |

## Roles

A role is a project on a machine, with its own settings:

```sh
role server psnr               labserver                       # a server is just another project
role host   simpsonsarcade-ps3 local   PLAYER=player1 PSNR=$(addr labserver)
role joiner simpsonsarcade-ps3 testbox PLAYER=player2 PSNR=$(addr labserver)
```

- The project's recipe says how to run it on that kind of machine (`RUN`,
  or `RUN_LINUX` on a Linux box). Its `RUN` line can use the role's settings
  (`$PLAYER`, `$PSNR`, ...) and the machine's (`$SIMPSONS_DIR`).
- Every role gets its own folder, log and pad mailbox (`$PAD`), so two roles
  never share files.
- `addr <machine>` is a machine's LAN address, for the others to reach it.

## Steps

Each is one `netlab play` step against a role's instance, and returns its
result, so a scenario can retry or bail out:

| Function | Does |
|---|---|
| `up <role>` / `down <role>` | start / stop its program |
| `wait_log <role> <text> [s]` | its log shows the text (a game's own log lines are the best state markers) |
| `wait_window <role> <title> [s]` | a window with that title is up |
| `press <role> <mask> [hold] [settle]` | a pad button through its mailbox (games that have one: ps3recomp) |
| `key <role> <combo> [settle]` | a key, e.g. `enter`, `alt+f`, `down` |
| `click <role> <x> <y> [settle]` | a click inside its window |
| `type_text <role> <text>` | typing |
| `snap <role> <name.png>` | its window, into `$SCEN_OUT/<role>/` |

A menu step that can be dropped (a press during a screen transition) should
retry on the log line that shows it worked, then back out and try again. See
[`simpsons-arcade/menu.sh`](simpsons-arcade/menu.sh).

## Adapting it to another program

1. **A recipe** for the program, if it doesn't have one (`projects/`), with a
   `RUN` line that takes what the scenario will vary: player name, server
   address, port. Settings come in as variables.
2. **How to tell where it is.** A log line per state is best (`room created`,
   `joined`, `game started`). Without one, a window title, or `snap` and look.
   If the program logs nothing useful, adding a line per state to the program
   is usually the cheapest fix.
3. **How to drive it.** Keys and clicks for a normal window; the program's
   own input hooks for a game (a pad mailbox, a scripted-input flag).
   Coordinates are inside the window, at the size it opens at.
4. **The script:** copy [`two-player-lan.sh`](two-player-lan.sh), keep the
   roles, and replace the steps in the middle.

## RA2 vs RA2 over the LAN

[`redalert2/lan.sh`](redalert2/lan.sh): this machine hosts, the test VM joins
(`scenarios/redalert2/lan.sh local testbox`). Both on one LAN, since the
game's IPX emulation finds games by broadcast: `nat/vm-to-lan.sh` first,
with the VM's machine file at its LAN address, and `nat/vm-to-nat.sh` after.
The VM needs the game in `RA2_GAME` and a player name of its own.

Each side plays a script in the game's own input (redalert2-recomp's
`tools/lan/host.args`, `joiner.args`: menu presses by dialog and control ID),
given through the role setting `RA2_ARGS`. The pictures are the game's own
frames, fetched from each side, not screen captures: a capture of the window
picks up whatever covers it. redalert2-recomp's `docs/netlab.md` has the
details.
