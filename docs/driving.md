# Driving a game from outside

`drive/` steers games with no one at the controller. It presses buttons,
waits for the game to reach a state, and looks at the screen, on this
machine or on another box over SSH. It needs three things from the game's
runtime, and nothing game-specific.

## The three hooks

1. **An input mailbox.** A file the runtime polls once per input poll. If it
   holds a button mask (and optionally how many polls to hold it), the
   runtime presses that and **empties the file**. The empty file is how the
   driver knows the press landed, so it never sends the next button into a
   screen that hasn't appeared yet.
2. **A log.** The runtime's own output, redirected to a file, with lines
   that say what the game did: a menu opened, a room was created, a peer
   connected. The driver waits for those lines. That's more reliable than
   waiting a fixed time, and it tells you which step failed.
3. **Frame dumps.** Every Nth presented frame written to a directory, so a
   person (or a script) can see what's on screen without anyone watching the
   window.

A runtime that has these can be driven with `drive/lib.sh` unchanged. Give it
a launcher that sets them up, in `games/<runtime>/`, like
[`games/ps3recomp/`](../games/ps3recomp/README.md).

## Instances

An instance is one running copy of a game: `drive/inst/<name>.env`.

- **`KIND=local`:** the paths are on this machine, and `START` is a shell
  command, usually the runtime's launcher.
- **`KIND=remote`:** a Windows box reached with `SSH` (and `JUMP`, if it
  sits behind another host). `start` runs a scheduled task there, so the game
  gets the logged-on desktop session rather than SSH's session 0.

Scenario scripts address instances by name. The same script then works
whether both players are on one machine, on two machines, or one of them is
behind a NAT: only the `.env` files change.

## Writing a scenario

```sh
NETLAB=$(cd "$(dirname "$0")/../.." && pwd)
. "$NETLAB/drive/lib.sh"
. "$NETLAB/games/ps3recomp/buttons.sh"

start a
wait_log a "ManagerGetStatus() -> ONLINE" 120 || { echo "a never came online"; exit 1; }
press a $START "" 10
...
snap a a.png
```

Some habits that paid off:

- **Retry on the log, not on time.** Menus drop presses that arrive during a
  transition. Loop "press, then wait a few seconds for the line that means it
  worked", with a retry limit.
- **Settle after each press.** The default is 2 seconds. Longer after
  anything that loads.
- **Clear the log before each run.** `start` does. A stale log from the last
  run matches every `wait_log` at once and makes a broken run look fine.
- **Check both sides.** For online play, look at both instances' frames at
  the end. One side can play on alone after the other dropped.
