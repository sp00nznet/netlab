# Roadmap

- **Checks on the builder:** a toolset `CHECK` step for toolkit tests that
  run on Linux (xboxrecomp conformance, pcrecomp difftest), right after the
  build.
- **Harnesses that test the farm's build:** Encarta's and ps3recomp's
  `regress.py` rebuild and test the checkout's own build; they need an exe
  option first.
- **Screen comparisons:** a `compare` step against a golden screenshot, with a
  tolerance.
- **More builder kinds:** Unity 6 (needs a licence on the builder), Rust with
  cargo-xwin (Tauri apps for Windows), .NET 8, Android, Docker.
- **Wine on the clangcl builder:** Inno Setup installers, and running
  `--selftest`-style checks on the builder itself.
- **An MCP server over `netlab`,** so agents without a shell can use the farm.
- **A queue:** today `netlab build` runs one job per call, and two calls can
  land on the same builder at once.
- **More runtimes in `games/`:** the Xbox 360 recompilations (xlive).
- **Scenario checks, not just captures:** compare the two frames (both
  players in the HUD, the same stage) and fail the run if they differ.
- **A second test box**, so both players of a NAT test can be behind routers,
  including two different NAT types.
- **Linux boxes** (`KIND=remote` over bash instead of PowerShell).
