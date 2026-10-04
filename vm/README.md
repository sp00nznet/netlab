# The Windows test box

A Windows 10 or 11 VM on Proxmox that logs itself on, reachable over SSH,
optionally with a real GPU passed through: a second machine to run and play
things on. One script makes it, from your workstation:

```sh
vm/setup-windows.sh
```

```
  asks: Proxmox host + SSH user, VM ID, storage, size, Windows ISO, account name
    │
    ├─ your key onto the host, if it isn't there (asks for the password once)
    ├─ the Windows ISO uploaded, if it's a file on this PC
    ├─ virtio-win: the one on the host, or downloaded there (asks first)
    ├─ vm/autounattend.xml + a random password ──> a small answer CD
    ├─ vm/create-vm.sh: the unattended install, 15-45 min
    ├─ the answer CD ejected and deleted (it holds the password)
    ├─ through the guest agent: SSH with your key, VC++ runtime, C:\netlab
    ├─ local/machines/<name>.env, so --on <name> works
    └─ optionally: a GPU passed through, and AMD's driver
  prints: the address, the account and its password (kept in local/secrets/)
```

Every answer goes into `lab.env` and is the default next time. Then:

```sh
./netlab run opennote --on testbox
```

## What you need

- **A Windows 10 or 11 ISO**, desktop edition, on the host or on your PC.
  Not Server: AMD's consumer GPU driver won't install on it. The answer file
  installs Pro (with Microsoft's generic install key, which doesn't
  activate); an ISO without Pro stops at the edition screen.
- **Root SSH to the Proxmox host** (the script offers to put your key there).
- **About 60 GB free** on the VM's storage. Thin storage only takes what
  Windows writes: about 26 GB with a GPU driver. Watch a thin pool above 90%:
  a full one damages every VM on it.
- **For a GPU:** IOMMU on (`amd_iommu=on iommu=pt` or `intel_iommu=on` on the
  kernel command line), and a card the host doesn't display on. Give it to
  vfio-pci first, which needs a host reboot:

  ```sh
  vm/vfio-host.sh            # shows what it would change
  vm/vfio-host.sh --apply && ssh $PVE_HOST reboot
  ```

  The setup script tells you if this is still to do, and `vm/attach-gpu.sh`
  attaches the card afterwards.

## The pieces, if you'd rather run them yourself

| Script | Does |
|---|---|
| `vm/autounattend.xml` | the answer file; `@USER@`, `@PASSWORD@`, `@NAME@` are filled in |
| `vm/create-vm.sh` | creates the VM from `lab.env` and waits out the install |
| `vm/guest-exec.sh <script.ps1> [K=V...]` | runs a PowerShell script in the VM as SYSTEM, through the guest agent |
| `vm/first-boot.ps1` | OpenSSH with your key, the network Private, no Windows Update or hibernation |
| `vm/prepare-game-box.ps1` | the VC++ runtime and `C:\netlab` |
| `vm/attach-gpu.sh` | the GPU on, the install CDs off |
| `vm/gpu-driver-amd.ps1` | AMD's display driver from the Adrenalin package, without AMD's installer |

The machine file it writes (`local/machines/<name>.env`): `KIND=remote`,
`SSH=<account>@<address>`, `DIR=C:/netlab`. Add `JUMP=root@<proxmox host>`
when the VM moves behind the NAT bridge (`nat/vm-to-nat.sh`).

## How it's put together, and why

- **The unattended install uses SATA.** It needs no driver during setup,
  so the answer file doesn't depend on which letter the virtio CD gets.
  First-logon installers find the virtio tools on D: to G:.
- **UEFI** shows "press any key to boot from CD". `create-vm.sh` presses
  Enter.
- **The guest agent** runs scripts as SYSTEM with no network (`guest-exec.sh`).
  That's how SSH gets set up, and how the IP gets changed when the VM moves
  networks.
- **The virtual display stays primary.** The Proxmox console keeps working,
  and a game's D3D12 device lands on the real card: the virtual one is
  display-only and can't render, so Windows' default adapter is the card.
  Games rendered in the VM run at 25-45 fps; copying frames from the card to
  the virtual display costs some.
- **Games run from a scheduled task** in the auto-logged-on desktop
  session, not from SSH, whose session 0 has no desktop.
- **Windows Update and hibernation are off**, so the thin disk doesn't grow
  by itself.

# The Linux test box

A Debian 13 VM whose desktop (Xfce) logs its user on by itself, so programs
started over SSH have a screen: native Linux builds run, play and pass QA
there. No GPU; Mesa renders in software.

```sh
vm/create-linux-vm.sh     # LINUX_* in lab.env; cloud-init does the rest (5-15 minutes)
```

It uses the Proxmox host's root SSH keys for the `netlab` user. Then describe
it as a machine, `local/machines/linuxbox.env`:

```sh
KIND=linux
SSH=netlab@<its address or name>
```

and use it with `--on linuxbox`. It comes from Debian's "generic" cloud
image: the "genericcloud" one has no graphics drivers, so LightDM finds no
screen to log on to.
