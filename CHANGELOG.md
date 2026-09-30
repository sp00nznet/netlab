# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- `drive/`: drive game instances on this machine or over SSH (start, stop,
  press, wait for a log line, snap a frame), with a CLI.
- `games/ps3recomp/`: launchers and notes for driving ps3recomp titles, and
  the remote installer that sets up a box's scheduled task.
- `vm/`: build a Windows 10 test VM on Proxmox unattended, pass a GPU
  through, set it up through the guest agent, install AMD's driver.
- `nat/`: a home-router NAT bridge on the Proxmox host, and moving the VM
  behind it and back.
- `servers/psnr-deploy.sh`: run a psnr server on a lab host.
- `scenarios/simpsons-arcade/`: an online match between two instances.
