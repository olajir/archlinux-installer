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
setup_logging "${INSTALLER_LOGFILE:-${installer_log_installed}}"

################################################################################
# Post-install
################################################################################

ensure_pacman_network

# Install the latest archlinux-keyring
echo -e "[${B}INFO${W}] Install the latest ${Y}archlinux-keyring${W} package"
pacman -Sy --noconfirm --color auto archlinux-keyring

# Install all packages
echo -e "[${B}INFO${W}] Install ${Y}pacman${W} packages"
pacman -Sy --noconfirm --needed --color auto "${default_packages[@]}"

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

# SMC / Apple keyboard (backlight is smc::kbd_backlight via applesmc)
cat > /etc/modules-load.d/macbook.conf << 'EOF'
applesmc
hid_apple
apple-gmux
i915
EOF
cat > /etc/modprobe.d/hid-apple.conf << 'EOF'
options hid_apple fnmode=1 iso_layout=1
EOF
# 11,3 discrete NVIDIA must stay off or S3 never returns
cat > /etc/modprobe.d/apple-discrete-gpu.conf << 'EOF'
blacklist nouveau
blacklist nvidia
blacklist nvidia_drm
options nouveau modeset=0
EOF
# Restore keyboard backlight after applesmc binds
cat > /etc/udev/rules.d/90-smc-kbd-backlight.rules << 'EOF'
ACTION=="add", SUBSYSTEM=="leds", KERNEL=="smc::kbd_backlight", ATTR{brightness}="128"
EOF

cat > /etc/modprobe.d/i915.conf << 'EOF'
options i915 enable_psr=0 enable_dc=0
EOF

# Panel backlight (gmux/intel) is not restored after S3; keyboard SMC is.
# Do not unload wl or toggle vgaswitcheroo here — that can freeze S3 so
# even the power button does not wake the machine.
cat > /usr/local/sbin/macbook-restore-display.sh << 'EOF'
#!/bin/sh
setpci -H1 -s 00:01.00 BRIDGE_CONTROL=0 >/dev/null 2>&1 || true

echo 0 > /sys/class/graphics/fb0/blank 2>/dev/null || true

for d in /sys/class/backlight/*; do
    [ -e "$d/brightness" ] || continue
    echo 0 > "$d/bl_power" 2>/dev/null || true
    saved="/run/macbook-backlight/$(basename "$d")"
    if [ -f "$saved" ]; then
        cat "$saved" > "$d/brightness" 2>/dev/null || true
    elif [ -e "$d/max_brightness" ]; then
        cat "$d/max_brightness" > "$d/brightness" 2>/dev/null || true
    fi
done

if [ -e /sys/class/leds/smc::kbd_backlight/brightness ]; then
    echo 128 > /sys/class/leds/smc::kbd_backlight/brightness || true
fi
EOF
chmod +x /usr/local/sbin/macbook-restore-display.sh

# Local sleep hooks belong in /etc, never in /usr/lib (that path must be a directory).
if [ -f /usr/lib/systemd/system-sleep ]; then
    rm -f /usr/lib/systemd/system-sleep
fi
mkdir -p /usr/lib/systemd/system-sleep /etc/systemd/system-sleep
cat > /etc/systemd/system-sleep/macbook-suspend << 'EOF'
#!/bin/sh
save_dir=/run/macbook-backlight
case "$1" in
    pre)
        mkdir -p "$save_dir"
        for d in /sys/class/backlight/*; do
            [ -e "$d/brightness" ] || continue
            cat "$d/brightness" > "$save_dir/$(basename "$d")" 2>/dev/null || true
        done
        ;;
    post)
        sleep 1
        /usr/local/sbin/macbook-restore-display.sh || true
        ;;
esac
EOF
chmod +x /etc/systemd/system-sleep/macbook-suspend

mkdir -p /etc/systemd/sleep.conf.d
cat > /etc/systemd/sleep.conf.d/macbook.conf << 'EOF'
[Sleep]
AllowSuspend=yes
SuspendState=mem
MemorySleepMode=deep
EOF

# Power off dGPU (vga_switcheroo) and unstick the 01:00 bridge for gmux backlight.
cat > /usr/local/sbin/macbook-gpu.sh << 'EOF'
#!/bin/sh
setpci -v -H1 -s 00:01.00 BRIDGE_CONTROL=0 >/dev/null 2>&1 || true
if [ ! -e /sys/kernel/debug/vgaswitcheroo/switch ]; then
    mount -t debugfs debugfs /sys/kernel/debug 2>/dev/null || true
fi
if [ -e /sys/kernel/debug/vgaswitcheroo/switch ]; then
    echo OFF > /sys/kernel/debug/vgaswitcheroo/switch || true
fi
EOF
chmod +x /usr/local/sbin/macbook-gpu.sh
cat > /etc/systemd/system/macbook-gpu.service << 'EOF'
[Unit]
Description=MacBook A1398: disable discrete GPU, fix gmux backlight
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/macbook-gpu.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl enable macbook-gpu.service

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
sed -i "s|^MODULES=(.*)|MODULES=(applesmc hid_apple apple-gmux i915)|" /etc/mkinitcpio.conf
mkinitcpio -P

# Create user
echo -e "[${B}INFO${W}] Generate user & password"
useradd -m -G wheel -s /bin/bash "${username}"
echo -e "${username} ALL=(ALL) ALL" > /etc/sudoers.d/${username}

# Change password for root & ${username}
set +x
if [[ "${install_mode}" == "auto" ]] ; then
    echo "root:${root_default_password}" | chpasswd
    echo "${username}:${username_default_password}" | chpasswd
else
    echo -e "Change password for user ${Y}root${W} :"
    passwd root
    echo -e "Change password for user ${Y}${username}${W} :"
    passwd "${username}"
fi
set -x

# Install bootloader and all necessary packages
# https://wiki.archlinux.org/title/Systemd-boot
echo -e "[${B}INFO${W}] Install & configure bootloader"
bootctl install

echo "default arch
timeout 8" > /boot/loader/loader.conf

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
    INSTALLER_LOGGING_TEE=1 INSTALLER_LOGFILE="${INSTALLER_LOGFILE}" bash ./archlinux-postinstall-desktop.sh
else
    echo -e "[${B}INFO${W}] Post-install complete!"
    echo -e "[${B}INFO${W}] Type ${Y}CTRL+D${W} and ${Y}reboot${W} to reboot in Arch!"
fi
