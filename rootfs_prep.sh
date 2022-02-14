#!/usr/bin/env bash

set -e

if [ "$(id -u)" -ne 0 ]; then
	echo 'Run as root or with sudo'
	exit 1
fi

USERNAME='user' # Set your username
HOSTNAME='hostname' # Pick your favorite name
REPO="https://repo-us.voidlinux.org"
HARDWARECLOCK='UTC' # Set RTC (Real Time Clock) to UTC or localtime
TIMEZONE='America/Chicago' # Set which region on Earth the user is
KEYMAP='us' # Define keyboard layout: us or br-abnt2 (include more options)
PKG_LIST='base-system openntpd git grub vim curl' # Install this packages (add more to your taste)
DEV_DISK_NAME='/dev/sda'
DEV_BOOT_PARTITION=${DEV_DISK_NAME}1
DEV_ROOT_PARTITION=${DEV_DISK_NAME}2
MOUNT_PATH='/mnt/sdcard'
ROOTFS_TARBALL='/home/me/Downloads/void-rpi3-PLATFORMFS-20210930.tar.xz' # Path to rootfs tarball.
PASSWORD='password' # Password for your user account

sfdisk --wipe-partitions always $DEV_DISK_NAME < fdisk-script # create partitions according to fdisk-script

mkfs.fat $DEV_BOOT_PARTITION # create boot filesystem
mkfs.ext4 -O '^has_journal' $DEV_ROOT_PARTITION # create ext4 filesystem on the root partition (with journaling)
#mkswap $DEV_SWAP_PARTITION # make the swap space on the second partition

# Mount the root partition
mount $DEV_ROOT_PARTITION $MOUNT_PATH
mkdir -p $MOUNT_PATH/boot
mount $DEV_BOOT_PARTITION $MOUNT_PATH/boot


# Extract rootfs to root partition
tar xvfJp $ROOTFS_TARBALL -C $MOUNT_PATH

# Copy emulation binary over so we can chroot from x86 to aarch64
cp /bin/qemu-aarch64-static $MOUNT_PATH/bin/

# Set up the xbps repo
echo "repository=${REPO}" > $MOUNT_PATH/etc/xbps.d/00-repository-main.conf

# Run a sync and update
env XBPS_ARCH=aarch64 xbps-install -Suy -r $MOUNT_PATH

# Pre-install some packages this can't be combined into the previous xbps-install
env XBPS_ARCH=aarch64 xbps-install -y -r $MOUNT_PATH $PKG_LIST

# Set the hostname of the machine
echo $HOSTNAME > $MOUNT_PATH/etc/hostname

# Set some locale stuff
cat >> $MOUNT_PATH/etc/rc.conf <<EOF
TIMEZONE="${TIMEZONE}"
KEYMAP="${KEYMAP}"
EOF

# Automount /tmp and /
cat > $MOUNT_PATH/etc/fstab <<EOF
# <file system> <dir> <type> <options> <dump> <pass>
tmpfs /tmp tmpfs defaults,nosuid,nodev 0 0
$(blkid $DEV_ROOT_PARTITION | cut -d ' ' -f 2 | tr -d '"') / ext4 rw,noatime,discard,commit=60,barrier=0 0 1
EOF

# Copy our keys over so we can access xbps repos
mkdir -p $MOUNT_PATH/var/db/xbps/keys/
cp -a /var/db/xbps/keys/* $MOUNT_PATH/var/db/xbps/keys/

# Copy our resolv.conf over so we can run xbps commands in the chroot before inital boot
# after inital boot we'll have dhcp dealing with all that
cp /etc/resolv.conf $MOUNT_PATH/etc/

# Set up ntpd so our clock is right which prevents cert verification errors
ln -s /etc/sv/openntpd $MOUNT_PATH/etc/runit/runsvdir/default/

# Run a bunch of stuff in the chroot
chroot $MOUNT_PATH /bin/bash -c "
# Make our user and user group
/bin/groupadd $USERNAME
/bin/useradd -g users -G wheel,storage,audio $USERNAME
# Set our password
echo '$USERNAME:$PASSWORD' | chpasswd
# We don't need grub and I couldn't make it just work :shrug:
#grub-install $DEV_DISK_NAME # Install grub
#update-grub
# Activate dhcp and ssh services for when we boot
ln -s /etc/sv/dhcpcd /etc/runit/runsvdir/default/
ln -s /etc/sv/sshd /etc/runit/runsvdir/default/
# Set up the xbps repo. Importantly, we have aarch64 at the end
echo 'repository=${REPO}/current/aarch64' > /etc/xbps.d/00-repository-main.conf
# Disable password auth
sed -ie 's/#PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
sed -ie 's/#KbdInteractiveAuthentication yes/KbdInteractiveAuthentication no/g' /etc/ssh/sshd_config
# Allow wheel group users to use sudo
sed -ie 's/# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/g' /etc/sudoers
# Not sure this is necessary, but it's listed here:
# https://docs.voidlinux.org/installation/guides/chroot.html
xbps-install -Suy xbps
xbps-install -uy
xbps-install -y base-system
xbps-remove -y base-voidstrap
xbps-reconfigure -fa
"

# Set up our ssh key
# this assumes your username on the main machine is the same as the username in the rootfs
mkdir $MOUNT_PATH/home/$USERNAME/.ssh
cat /home/$USERNAME/.ssh/id_rsa.pub > $MOUNT_PATH/home/$USERNAME/.ssh/authorized_keys

# Clean up the emulation thing
rm $MOUNT_PATH/bin/qemu-aarch64-static

umount $MOUNT_PATH/boot
umount $MOUNT_PATH

echo "Done"
