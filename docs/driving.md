# Driving a game from outside

netlab steers programs with no one at the controls: `netlab play` steps and
the scenario library ([`scenarios/`](../scenarios/README.md)) press buttons,
wait for the program to reach a state, and look at the screen, on this
machine or another over SSH. For a game, it needs three things from the
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

A runtime that has these can be driven as it is: its recipe's `RUN` line
points the mailbox at `$PAD` (one per instance) and its log goes to the
instance's log, which `expect-log` reads. Window screenshots (`snap`) stand in
for frame dumps when the game draws to a window. See
[`games/ps3recomp/`](../games/ps3recomp/README.md) for one runtime's hooks.

## Writing a scenario

See [`scenarios/README.md`](../scenarios/README.md): roles (a project on a
machine), and steps against them. Some habits that paid off:

- **Retry on the log, not on time.** Menus drop presses that arrive during a
  transition. Loop "press, then wait a few seconds for the line that means it
  worked", with a retry limit.
- **Settle after each press.** The default is 2 seconds. Longer after
  anything that loads.
- **Clear the log before each run.** `up` does (each run writes a new one). A stale log from the last
  run matches every `wait_log` at once and makes a broken run look fine.
- **Check both sides.** For online play, look at both instances' frames at
  the end. One side can play on alone after the other dropped.
