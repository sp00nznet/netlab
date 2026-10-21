# Handing the lab to an agent

netlab was built to be driven by an AI coding agent as much as by a person.
Every step is a command that prints what happened and exits with a code
that means something, and every result an agent needs to look at is a file:
a log, a report, a PNG of the program's window.

```
  you: "build rol, run it on the test box, and check the menu works"
   │
   v
  agent ── ./netlab build rol ───────────> builder        reads: candidates, build wall, errors
     │
     ├──── ./netlab run rol --on testbox ───> Windows VM
     ├──── ./netlab play rol menu.qa ───────> keys, waits, snaps
     │                                         reads: the PNGs, qa.log
     ├──── fixes the code in your checkout
     └──── ./netlab check rol ──────────────> build + qa again, until PASS
```

## Claude Code

The repo carries a skill, [`.claude/skills/netlab/SKILL.md`](../.claude/skills/netlab/SKILL.md),
that teaches Claude the commands, how to read their output, and the rules
(what not to publish, what not to type into). Started in this checkout,
Claude Code loads it by itself.

To use the lab from your projects' own checkouts, where you do most of your
work, make the skill global and tell it where netlab is:

```sh
mkdir -p ~/.claude/skills
cp -r .claude/skills/netlab ~/.claude/skills/        # or a symlink, to keep it current
```

Then, in the project's `CLAUDE.md`:

```markdown
Builds and tests go through netlab at ~/src/netlab (the netlab skill):
`~/src/netlab/netlab check yourapp`. Its recipe is projects/yourapp.env.
```

Things to ask for that work well:

- "Build yourapp on the farm and tell me what failed."
- "Run it on the Linux box and show me the main window."
- "Write a QA steps file that opens every menu and screenshots each, and add
  it to the recipe."
- "Bench yourapp on every builder."
- "A/B: build main and my branch in two slots and compare the outputs."
- "Write a recipe for ~/src/newthing; it's a Godot 4.6 game."

## Other agents

Anything that can run a shell command and read a file can drive netlab:
point it at the skill file as its instructions, or paste the command list
from the top of `netlab` (`./netlab` with no arguments prints it). The pieces an agent
needs are all text:

| It needs to know | From |
|---|---|
| what can be built | `./netlab projects` |
| whether a build passed | the exit code; `./netlab log <p>` for why |
| whether QA passed | exit 0 PASS, 1 FAIL, 3 SKIP; `local/qa/<p>/<time>/qa.log` |
| what's on screen | the PNGs from `snap` and `play`, which a multimodal model can read |
| the farm's state | `./netlab status` |
| who's using a machine | `./netlab locks`; exit 4 = gave up waiting for one |

## Two agents, one lab

Several agents (or an agent and you) can use the lab at once, but a test
machine's desktop is one: two QA runs on it at once steal each other's
focus and spoil both. So every command that puts something on a machine
(`run`, `play`, `snap`, `stop`, `qa`, and `check`'s QA) takes that
machine's lock, `local/locks/<machine>.lock`, and waits for another job's:

```
netlab: waiting for linuxbox, held by qa-hover, pid 16964 (netlab qa hover --on linuxbox) since 2026-10-21 14:02:11
netlab: got linuxbox
```

- `run` keeps its lock after it returns, until `netlab stop` or the end of
  the job (a failed `run` lets go at once). "The job" is the agent process
  (`claude.exe`) plus `NETLAB_JOB`, not the shell, so its later
  `play`/`snap`/`stop` calls don't wait on it; another job does. Subagents
  of one Claude Code session share that process: parallel ones must each
  set their own `NETLAB_JOB` (e.g. `NETLAB_JOB=$NETLAB_JOB/tester`) on
  every call to keep out of each other's way.
- After `NETLAB_LOCK_TIMEOUT` seconds (default 1800, `0` = fail at once)
  the command gives up with exit code **4**.
- A lock whose holder died (a crashed job, a killed shell) is stale: the
  next command removes it and goes ahead. Ctrl-C lets go too.
- Scenarios take all their machines at the first `up`, in name order (so
  two scenarios can't deadlock), and let go when the script ends.
- Work outside netlab, over plain ssh, needs the lock too:
  `./netlab lock linuxbox -- ssh linuxbox 'DISPLAY=:0 ./test.sh'`, or
  `./netlab lock linuxbox` ... `./netlab unlock linuxbox`.
- `./netlab locks` shows who holds what. `./netlab unlock <machine>` lets
  go of your own or a stale lock; another job's live one takes `--force`:
  check first that that job has really stopped.
- `NETLAB_JOB=<name>` names the holder in those messages. The factory sets
  it to the job's id.

Builders aren't locked: `build` places jobs by load. The locks are files on
the machine running netlab, so two controllers (two workstations) don't see
each other's.

## Keeping it safe

The agent runs as you, with your SSH keys. The skill's rules, and why:

- **Ask before `netlab ship`.** It publishes: a GitHub release, an itch.io
  build. Claude asks first; give other agents the same rule.
- **`SHIP=lan` builds stay on the LAN.** Anything built from retail software
  or data is marked so in its recipe; an agent mustn't upload or attach it.
- **Screenshots are of the program's window only**, never the whole
  desktop, so your other windows don't end up in a transcript.
- **No typing into programs on your own machine** with real data; use a test
  VM for steps that change things.
- **Hosts and paths stay in `local/`**, never in tracked files.
- **Don't edit `netlab` or `farm/build.sh` while a job runs**: bash reads
  scripts as it goes, and the running job breaks.

If you'd rather the agent not reach the Proxmox hosts at all, give it a
workstation account whose SSH keys only open the builders and test
machines; the build/run/qa loop needs Proxmox root only as the SSH hop to a
VM behind the NAT bridge (`JUMP`). Making
builders and VMs (`builders/create.sh`, `vm/`, `nat/`) does.
