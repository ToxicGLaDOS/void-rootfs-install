# Prerequisites

1. This script expects to be run on a voidlinx machine, mostly because it uses `xbps` outside the `chroot` and copies `xbps` keys from your local machine into the `chroot`.
2. This script requires the machine you're running it on to have the `binfmt-support` and `qemu-user-static` packages installed to `chroot` into the aarch64 system.

This should cover both 1 and 2:
```bash
sudo xbps-install binfmt-support qemu-user-static # Install required packages
sudo ln -s /etc/sv/binfmt-support /var/service/ # Enable the binfmt-support service
```
