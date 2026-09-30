# The Simpsons Arcade Game, online

An online match between two driven instances of the ps3recomp build
([simpsonsarcade-ps3](https://github.com/sp00nznet/simpsonsarcade-ps3)) over
a [psnr](https://github.com/sp00nznet/psnr) server:

```sh
scenarios/simpsons-arcade/match.sh a b captures/
```

`a` hosts, `b` joins. What the run tests depends only on the instances'
`drive/inst/*.env`:

| Test | `a` (host) | `b` (joiner) | psnr |
|---|---|---|---|
| One machine | local, `P2P_PORT=3658` | local, `P2P_PORT=3659`, its own `DIR` | local |
| Two machines on a LAN | local | remote: the test VM on the LAN | either machine |
| Host behind a NAT | remote: the VM behind the NAT bridge (`JUMP` set) | local | a third LAN host |
| Joiner behind a NAT | local | remote: the VM behind the NAT bridge | a third LAN host, with `-relay` |

- **"Joiner behind a NAT" needs the relay.** The host opens the game-setup
  stream to the joiner, and nothing can connect in to a player behind a
  router.
- **"Host behind a NAT" doesn't.** The host connects out.
- **Players are named by `PLAYER`**, and names must differ: psnr refuses a
  second player with a name already taken.

## Verified

As of 2026-09-30, with ps3recomp#200 and psnr's relay:

- **Two machines on a LAN:** this PC hosting, the test VM joining.
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
