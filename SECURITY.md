# Security

This lab drives your hypervisor as root and your test box as an
administrator, over SSH keys. Keep it on your own network.

- **No secrets or hosts live in the repo.** `lab.env`, `drive/inst/*.env`,
  `local/` (checkouts, machines, private recipes), `farm/builders` and
  `farm/times` hold your hosts, paths and addresses and are git-ignored. The
  SSH key is yours, from `~/.ssh`. Don't put passwords in any of them.
- **Builders are containers you own,** reached as root over SSH. A build runs
  the project's own build scripts there, so only point the farm at code you
  trust.
- **The scripts change the Proxmox host:** VMs, a runtime bridge and
  iptables rules (all tagged `netlab-nat`), and with `vm/vfio-host.sh
  --apply`, a modprobe file and the initramfs. Each says so at the top.
- **The test box auto-logs on its user** (that's what lets games run
  unattended in a desktop session), has Windows Update off, and accepts SSH
  as an administrator with your key. Treat it as a lab machine, not a
  personal one.

To report a problem, open a private security advisory on the repository.
