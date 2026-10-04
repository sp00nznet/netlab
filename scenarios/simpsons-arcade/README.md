# The Simpsons Arcade Game, online

An online match between two copies of the ps3recomp build
([simpsonsarcade-ps3](https://github.com/sp00nznet/simpsonsarcade-ps3)) over
a [psnr](https://github.com/sp00nznet/psnr) server, all three started by the
scenario ([`../lib.sh`](../lib.sh)):

```sh
scenarios/simpsons-arcade/match.sh <host machine> <joiner machine> <server machine>
scenarios/simpsons-arcade/match.sh local testbox labserver
```

The host creates a match, the joiner quick-matches in, both pick a
character, the host starts, and both windows are captured in Stage 1. The
server is psnr's recipe run on the server machine (`PSNR_FLAGS=-relay` in
its machine file when a player is behind a NAT). Each machine says where its
copy of the game's data is (`SIMPSONS_DIR`). Which network test it is depends
only on the machines:

| Test | host | joiner | server |
|---|---|---|---|
| Two machines on a LAN | this one | the test VM on the LAN | any LAN host |
| Host behind a NAT | the VM behind the NAT bridge (`JUMP` in its machine file) | this one | a LAN host |
| Joiner behind a NAT | this one | the VM behind the NAT bridge | a LAN host, with `-relay` |

- **"Joiner behind a NAT" needs the relay.** The host opens the game-setup
  stream to the joiner, and nothing can connect in to a player behind a
  router.
- **"Host behind a NAT" doesn't.** The host connects out.
- **Players are named by `PLAYER`**, set per role in `match.sh`; psnr refuses
  a second player with a name already taken.

## Verified

As of 2026-10-02, on the scenario library with farm builds: **joiner behind
a NAT**. The workstation (the `local` machine: a Windows desktop on the
LAN) hosted, the Windows test VM joined from behind the NAT bridge through
the relay, and both reached Stage 1 with both players in the HUD.

As of 2026-09-30, with ps3recomp#200 and psnr's relay:

- **Two machines on a LAN:** the workstation (`local`) hosting, the test VM joining.
- **Host behind a NAT:** the VM hosting from behind the NAT bridge.
- **Joiner behind a NAT:** the VM joining from behind the NAT bridge. The
  game setup went through the relay.

In each run both reached Stage 1 in sync.

## What a working match looks like

- **The host's log:** `created room`, `signaling: member 2 (…)`, then the
  game setup going out over the P2P stream: three `send` calls of about
  3.5 KB in all, compressed by the game's own zlib.
- **The joiner's log:** `joined room`, then `accept(…)` and the setup
  arriving in a `recv`.
- **Both frames:** Stage 1 with both players in the HUD, in step with each
  other.

If one side shows "MATCH DISCONNECT", check both frame rates in the logs
(`[fps]`). A host that drops to a few fps (another heavy job on its machine,
or `PS3_VERBOSE` left on) misses the lobby's timing and kicks the joiner.
