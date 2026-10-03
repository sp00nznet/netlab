# The Windows test box

A Windows 10 VM on Proxmox with a real GPU passed through: a second machine
to play against, that recompiled games render on at full speed. Everything
runs from your workstation, with `lab.env` filled in and root SSH to the
Proxmox host.

## What you need on the Proxmox host

- **IOMMU on:** `amd_iommu=on iommu=pt` (or `intel_iommu=on`) on the kernel
  command line, and the vfio modules in `/etc/modules`.
- **A GPU it can give away:** it can't be the one the host itself displays
  on; `video=efifb:off` helps.
- **In `ISO_DIR`:**
  - a Windows 10/11 ISO. Not Server: AMD's consumer driver won't install on
    Server;
  - the virtio-win ISO;
  - an image with an `autounattend.xml` at its root that creates a local
    admin account (`VM_USER`), logs it on automatically, and installs the
    virtio guest tools and QEMU guest agent from the virtio CD at first logon.
    `mkunattend.py` describes the layout it expects.
- **About 60 GB free** on `VM_STORAGE`. It's thin, so the VM only takes
  what it writes: about 26 GB with the driver installed. Watch a thin pool
  above 90%; a full one damages every VM on it.

## Build it

```sh
vm/vfio-host.sh --apply && ssh $PVE_HOST reboot   # once per host; see the script first
vm/build-setup-iso.sh                             # virtio drivers + your answer file, one CD
vm/create-vm.sh                                   # unattended install; waits for the guest agent
vm/guest-exec.sh vm/first-boot.ps1 PubKey="$(cat ~/.ssh/id_rsa.pub)"   # SSH, Private network, no WU
vm/attach-gpu.sh                                  # the GPU goes on after the install
scp vm/gpu-driver-amd.ps1 vm/prepare-game-box.ps1 $VM_USER@<vm-ip>:C:/Users/$VM_USER/
ssh $VM_USER@<vm-ip> "powershell -ExecutionPolicy Bypass -File gpu-driver-amd.ps1 -Url <AMD driver URL>"
ssh $VM_USER@<vm-ip> "powershell -ExecutionPolicy Bypass -File prepare-game-box.ps1"
```

Then describe it as a machine (`local/machines/testbox.env`: `KIND=remote`,
`SSH`, and `JUMP` when it's behind the NAT bridge) and use it with
`--on testbox`. `netlab run` copies each build over and starts it in the
desktop session.

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
