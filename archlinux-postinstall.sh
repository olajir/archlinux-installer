#!/bin/bash
################################################################################
# Author  : David Calvert
# Purpose : Arch Linux custom post-installer
# GitHub  : https://github.com/dotdc/archlinux-installer
################################################################################

set -e

################################################################################
# Source variables
################################################################################

. config-variables.sh

################################################################################
# Post-install
################################################################################

# Install the latest archlinux-keyring
echo -e "[${B}INFO${W}] Install the latest ${Y}archlinux-keyring${W} package"
pacman -Sy --color auto archlinux-keyring

# Install all packages
echo -e "[${B}INFO${W}] Install ${Y}pacman${W} packages"
pacman -Sy --color auto "${default_packages[@]}"

# Configuration
echo -e "[${B}INFO${W}] Configure system localization"
ln -sf /usr/share/zoneinfo/"${timezone}" /etc/localtime
hwclock --systohc
sed -i "s|^#${locale}.UTF-8|${locale}.UTF-8|" /etc/locale.gen
locale-gen
echo "LANG=${locale}.UTF-8" > /etc/locale.conf
echo "KEYMAP=${keymap}" > /etc/vconsole.conf
echo "${hostname}" > /etc/hostname

# Broadcom wl (BCM4360 on MacBookPro A1398) — avoid conflict with in-kernel brcm drivers
echo -e "[${B}INFO${W}] Configure Broadcom wireless (wl)"
mkdir -p /etc/modprobe.d /etc/modules-load.d
cat > /etc/modprobe.d/broadcom-wl.conf << 'EOF'
blacklist b43
blacklist b43legacy
blacklist ssb
blacklist bcm43xx
blacklist brcm80211
blacklist brcmfmac
blacklist brcmsmac
blacklist bcma
EOF
echo "wl" > /etc/modules-load.d/broadcom-wl.conf

# Configure mkinitcpio hooks
echo -e "[${B}INFO${W}] Generate mkinitcpio hooks"

# systemd initramfs: sd-encrypt + sd-vconsole (not the busybox encrypt/keymap hooks)
# https://wiki.archlinux.org/title/Dm-crypt/Encrypting_an_entire_system#LVM_on_LUKS
if [[ "${luks}" == "true" ]] ; then
    mkinitcpio_hooks="base systemd autodetect keyboard sd-vconsole modconf kms block sd-encrypt lvm2 filesystems fsck"
else
    mkinitcpio_hooks="base systemd autodetect keyboard sd-vconsole modconf kms block lvm2 filesystems fsck"
fi

sed -i "s|^HOOKS=(.*)|HOOKS=(${mkinitcpio_hooks})|" /etc/mkinitcpio.conf
mkinitcpio -P

# Create user
echo -e "[${B}INFO${W}] Generate user & password"
useradd -m -G wheel -s /bin/bash "${username}"
echo -e "${username} ALL=(ALL) ALL" > /etc/sudoers.d/${username}

# Change password for root & ${username}
if [[ "${install_mode}" == "auto" ]] ; then
    echo "root:${root_default_password}" | chpasswd
    echo "${username}:${username_default_password}" | chpasswd
else
    echo -e "Change password for user ${Y}root${W} :"
    passwd root
    echo -e "Change password for user ${Y}${username}${W} :"
    passwd "${username}"
fi

# Install bootloader and all necessary packages
# https://wiki.archlinux.org/title/Systemd-boot
echo -e "[${B}INFO${W}] Install & configure bootloader"
bootctl install

echo "default arch
timeout 1" > /boot/loader/loader.conf

# shellcheck disable=SC2154
uuid=$(blkid -s UUID -o value "${os_partition}")

if [[ "${luks}" == "true" ]] ; then
    boot_options="rd.luks.name=${uuid}=${lvm_name} root=/dev/mapper/SYSTEM-root rw ${kernel_extra_params}"
else
    boot_options="root=/dev/mapper/SYSTEM-root rw ${kernel_extra_params}"
fi

cat > /boot/loader/entries/arch.conf << EOF
title Arch Linux
linux /vmlinuz-linux
initrd /intel-ucode.img
initrd /initramfs-linux.img
options ${boot_options}
EOF

mkdir -p /etc/pacman.d/hooks

echo "
[Trigger]
Type = Package
Operation = Upgrade
Target = systemd

[Action]
Description = Updating systemd-boot
When = PostTransaction
Exec = /usr/bin/bootctl update" > /etc/pacman.d/hooks/100-systemd-boot.hook

################################################################################
# Desktop specific
################################################################################

if [[ "${install_type}" == "desktop" ]] ; then
    echo -e "[${B}INFO${W}] Desktop specific post-install"
    bash ./archlinux-postinstall-desktop.sh
else
    echo -e "[${B}INFO${W}] Post-install complete!"
    echo -e "[${B}INFO${W}] Type ${Y}CTRL+D${W} and ${Y}reboot${W} to reboot in Arch!"
fi
