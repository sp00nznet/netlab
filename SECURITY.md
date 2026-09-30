# Security

This lab drives your hypervisor as root and your test box as an
administrator, over SSH keys. Keep it on your own network.

- **No secrets live in the repo.** `lab.env` and `drive/inst/*.env` hold your
  hosts and addresses and are git-ignored; the SSH key is yours, from
  `~/.ssh`. Don't put passwords in either.
- **The scripts change the Proxmox host:** VMs, a runtime bridge and
  iptables rules (all tagged `netlab-nat`), and with `vm/vfio-host.sh
  --apply`, a modprobe file and the initramfs. Each says so at the top.
- **The test box auto-logs on its user** (that's what lets games run
  unattended in a desktop session), has Windows Update off, and accepts SSH
  as an administrator with your key. Treat it as a lab machine, not a
  personal one.

To report a problem, open a private security advisory on the repository.
