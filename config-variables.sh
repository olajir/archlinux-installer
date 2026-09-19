#!/bin/bash

# Target: MacBookPro A1398 (Retina 15", Late 2013 / Mid 2014)

# server or desktop
install_type="desktop"

# manual or auto
install_mode="manual"

# luks or no-luks (LVM inside LUKS)
luks="true"

if [[ "${luks}" == "true" ]] ; then
    part_name="LUKS-SYSTEM"
    lvm_name="cryptlvm"
else
    part_name="SYSTEM"
    lvm_name="lvm"
fi

################################################################################
# Default variables
################################################################################

# Colors
W='\e[0m'  # White
R='\e[91m' # Red
G='\e[92m' # Green
B='\e[96m' # Blue
Y='\e[93m' # Yellow

# LVM Configuration
create_home_fs="true"

lv_swap_size="16G"
lv_root_size="150G"
lv_home_size="100%FREE"

# Configuration
keymap="sv-latin1"
# GNOME/xkb: Swedish Apple keyboard on MacBook
xkb_layout="se+mac"
hostname="MacBookPro-arch"
timezone="Europe/Stockholm"
locale="sv_SE"
username="ola"
username_default_password="0laskol@"
root_default_password="0lask0l@"

# Kernel parameters for A1398 suspend/resume
kernel_extra_params='acpi_osi=Darwin pcie_aspm=force'

# Default packages
declare -a default_packages=(
    "bash-completion"
    "dkms"
    "git"
    "openssh"
    "vim"
    "wget"
    "linux-headers"
    "broadcom-wl-dkms"
    "wireless_tools"
)

################################################################################
# Desktop variables
################################################################################

# Gnome favorite apps
# Can be found in /usr/share/applications/
favorite_apps="['org.gnome.Terminal.desktop', 'nautilus.desktop', 'brave-browser.desktop', 'vivaldi-stable.desktop', 'firefox.desktop', 'visual-studio-code.desktop', 'notion-app.desktop', 'spotify.desktop', 'slack.desktop', 'discord.desktop', 'scummvm.desktop']"

# Desktop specific packages
declare -a desktop_packages=(
    "bluez"
    "bluez-utils"
    "cups"
    "cups-pdf"
    "docker"
    "gdm"
    "github-cli"
    "gnome"
    "gparted"
    "networkmanager"
    "power-profiles-daemon"
    "unrar"
    "unzip"
    "usbutils"
    "virtualbox"
    "virtualbox-guest-utils"
    "virtualbox-host-modules-arch"
    "vlc"
    "zip"
    "zsh"
)

# AUR packages
declare -a aur_packages=(
    "spotify"
    "google-chrome"
    "slack-desktop"
    "visual-studio-code-bin"
)
