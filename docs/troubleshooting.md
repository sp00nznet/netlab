# Troubleshooting

Everything here happened while building this lab.

## The test box

- **AMD's driver won't install on Windows Server.** Its INF lists only the
  desktop product type, so the card stays on "Microsoft Basic Display
  Adapter". Use Windows 10/11.
- **QEMU crashes on the VM's second start** (`pci_irq_handler: Assertion …`,
  after "failed to reset PCI device"). The card was left in a bad state when
  the host driver had it, or when the last VM stopped. Bind it to vfio-pci
  from boot (`vm/vfio-host.sh`) and reboot the host.
- **Never PCI remove/rescan a stuck card.** It can go to D3cold and drop off
  the bus ("Unable to change power state from D3cold to D0"); only a host
  reboot brings it back.
- **Windows Setup stops at "Press any key to boot from CD".** That's UEFI.
  `create-vm.sh` sends Enter; if you start the VM by hand, press it yourself.
- **SSH to the box times out.** Windows put the network in the Public
  profile, and a rule scoped to Private doesn't apply. `first-boot.ps1` sets
  Private and scopes the SSH rule to any profile.
- **SSH says "Host key verification failed"** after a rebuild or a move: DHCP
  handed the box an address another machine had. Compare the fingerprint
  the box reports (`guest-exec.sh` running
  `ssh-keygen -lf C:\ProgramData\ssh\ssh_host_ed25519_key.pub`) with
  `ssh-keyscan`, then `ssh-keygen -R <ip>`.
- **The thin pool fills.** A driver package and its extracted copy are 4-5
  GB; Windows Update grows it too. `gpu-driver-amd.ps1` cleans up and trims,
  and `first-boot.ps1` turns updates off. `Optimize-Volume -DriveLetter C
  -ReTrim` hands freed blocks back (the disk has `discard=on`).
- **A game started over SSH renders nothing:** it's in session 0. Start it
  through the scheduled task (`drive/lib.sh start` does).
- **"Running scripts is disabled on this system":** Windows 10 ships with the
  execution policy Restricted. `first-boot.ps1` sets RemoteSigned; before
  that, run scripts with `powershell -ExecutionPolicy Bypass -File …`.

## Driving

- **Every `wait_log` passes at once, and the run "works" but nothing
  happened.** The log is stale. On the box, the scheduled task stays
  "Running" after its game is killed, so `schtasks /Run` does nothing and the
  old log remains. `start` ends the task and deletes the log first; do the
  same in anything you write by hand.
- **Presses get lost.** They arrived during a screen transition. Retry on
  the log line that proves the step worked; see `scenarios/*/menu.sh`.
- **The game crawls at 1 fps** (ps3recomp). `PS3_VERBOSE` is on: with stderr
  redirected, the runtime logs every wait. Set `PS3_VERBOSE=0`; the
  launchers do.
- **A host kicks its joiner right after the lobby.** Check both frame
  rates. A host starved of CPU (another build on the machine) misses the
  lobby's timing.

## Networks

- **The NAT bridge passes nothing.** The host's FORWARD chain defaults to
  DROP (Docker sets that); `nat-up.sh` adds the accepts. Also check
  `ip_forward`.
- **Hole punching fails behind a Linux router that accepts everything.** A
  peer's early punch gets recorded as a connection, holds the port, and the
  router gives its own player a different public port. Real home routers
  drop unsolicited traffic, and so does `nat-up.sh`.
- **Docker "internal" networks drop packets addressed off their subnet**,
  even on the way to a router container. (That's in psnr's own Docker NAT
  lab, `psnr/lab/`.)
- **`pkill -f <path>` over SSH kills its own shell**, because the pattern
  matches the command line carrying it. Use `pkill -x <name>`.
