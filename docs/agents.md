# Handing the lab to an agent

netlab was built to be driven by an AI coding agent as much as by a person.
Every step is a command that prints what happened and exits with a code
that means something, and every result an agent needs to look at is a file:
a log, a report, a PNG of the program's window.

```
  you: "build kotor, run it on the test box, and check the menu works"
   │
   v
  agent ── ./netlab build kotor ─────────> builder        reads: candidates, build wall, errors
     │
     ├──── ./netlab run kotor --on testbox ─> Windows VM
     ├──── ./netlab play kotor menu.qa ─────> keys, waits, snaps
     │                                         reads: the PNGs, qa.log
     ├──── fixes the code in your checkout
     └──── ./netlab check kotor ────────────> build + qa again, until PASS
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
