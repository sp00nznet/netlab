# QA: the checks your projects already have

`netlab qa` doesn't bring its own test framework. It runs a project's own
check as `QA` (the exit code decides), plays `QA_STEPS` against the running
program, and keeps what both left behind. This page is what exists in the
projects so far, and how each plugs in.

## What decides pass or fail

| Harness | Command | Decides by | Watch out for |
|---|---|---|---|
| OpenNote self-test | `OpenNote.exe --selftest` | exit code; `ok` / `FAIL name: why` lines | GUI-subsystem exe, but headless |
| OpenNote document round-trip | `py tests/make_fixtures.py build/corpus`, `OpenNote.exe --docx-check build/corpus`, `py tests/validate_docx.py build/corpus/out` | exit codes, `FAIL` lines | an empty corpus is a skip |
| Encarta | `py tools/regress.py [--full]` | exit code; `ok`/`FAIL`/`skip` lines, `N passed, N failed, N skipped` | a missing CD is a **skip with exit 0**; it checks the checkout's own build |
| ps3recomp regression gate | `python tools/regress.py check <port>\|--all` | milestone log against a golden: LOST, UNRESOLVED and DROPPED fail | exit 2 is "the toolkit didn't build", not a regression; a port that isn't there is `SKIPPED`; reruns a red once |
| xboxrecomp | `py -3 -m pytest tools/` and `py -3 -m tools.conformance` | exit codes; `FAIL <name>` lines | a missing phase prints `phase SKIPPED` and **exits 0** |
| pcrecomp | `python tools/lift/difftest.py`, many `--selftest` flags | exit code; `ok`/`FAIL` lines | needs unicorn, capstone and a C compiler |
| systemes3recomp, lindberghrecomp | `ctest` (`*_rt_selftest`, `cpu_selftest`) | exit code | x86 Windows exes: run them on Windows |
| androidrecomp | `python tools/selftest.py` | exit code | runs anywhere once `arc_host` is built |

A skip that exits 0 isn't a pass. `QA_SKIP` is a regex for how a harness says
it skipped something, and when it matches, `netlab qa` reports SKIP (exit 3),
not PASS:

```sh
QA='py tools\regress.py'
QA_SKIP='[1-9][0-9]* skipped'                        # Encarta
QA_SKIP='phase SKIPPED|[1-9][0-9]* skipped'          # xboxrecomp conformance
QA_SKIP='\] SKIPPED'                                  # ps3recomp regress.py
```

## Projects with no gate: reached a state, left frames

Most games have input and capture hooks but nothing that decides pass or
fail. For them, QA is "it got there": `expect-log` for the line that marks
the state, `expect-window`, and `snap`. Their own flags do the driving, in
`RUN` or a QA-only command line:

| Project | Input | Waits on | Captures |
|---|---|---|---|
| ps3recomp titles | `PAD_FILE` mailbox (`pad` steps), `PAD_SCRIPT="t:mask,..."` | log lines (`[cellPad] PAD_FILE press`, network state) | `LD_FRAME_DUMP` (ppm) |
| Burnout 3 | `RECOMP_PAD_SCRIPT="ms:btn[:hold],..."`, `RECOMP_PAD_LIVE` | the log naming opened files (`_FEMain.xmv` = title screen) | `RECOMP_FB_DUMP` (bmp), `--record` |
| Force Commander | `--click X Y`, `--key VK`, `--clickat`, `--clickgap`; `--nocond`, `--varat` | `--watchdog s` | `--dumpframe`, `--screenshot` |
| Rise of Legends | `--click x,y@sec`, `--key vk@sec` (video time) | `--watchdog s`, `--frames N` | `--record out.mp4` |
| androidrecomp | JNI calls at a frame: `--entry=...pointerPressed --args=x,y,0 --entry-at=frame:N` | `--frames N` | `--shot` |
| Goalblins (Godot) | `res://tools/shoot.tscn -- <scene> <out.png>` | frames | PNGs |
| ordinary windowed apps | `key`, `click`, `type` steps | `expect-window`, `expect-log` | `snap` |

## Where each can run

- **On a Linux builder, no game data:** xboxrecomp pytest and conformance (in
  its Docker images), pcrecomp difftest and self-tests, ps3recomp pytest,
  androidrecomp `selftest.py`. These belong after the build, on the builder.
- **On Windows, no game data:** OpenNote, the systemes3/lindbergh ctest binaries.
- **Needs your game data:** ps3recomp `regress.py`, Encarta `regress.py`, the
  game drivers above. They run on a machine that has the data, named in its
  `local/machines/<name>.env`.
- **Needs a GPU or a display:** ps3recomp `--shots`, Rise of Legends
  recording, Force Commander (DirectDraw), Goalblins captures.

## Still to do

- Harnesses that rebuild the checkout themselves (Encarta's and ps3recomp's
  `regress.py`) test that build, not the farm's. Each needs a way to be
  pointed at an exe (like Encarta's `run-encarta.ps1 -Harness`) before it can
  gate a farm build.
- Toolkit checks that run on Linux should run on the builder right after the
  build (a `CHECK` step in the toolset), so a broken toolkit never reaches a
  test machine.
