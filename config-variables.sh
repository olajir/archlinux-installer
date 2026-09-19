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

# A1398: no acpi_osi=* — Darwin blocks S3 resume, !Darwin breaks SMC (kbd backlight).
# intel_iommu=off: IOMMU remap after S3 hangs many Apple Intel machines.
# nouveau.modeset=0: 11,3 dGPU left powered prevents resume; use iGPU only.
# i915.enable_psr/dc=0: panel power-saving that often leaves a black screen after S3.
# Do not set enable_rc6=0/enable_fbc=0 — that combo stopped power-button wake.
# hid_apple.fnmode=1: F5/F6 are keyboard-backlight keys (macOS layout).
kernel_extra_params='intel_iommu=off mem_sleep_default=deep i915.enable_psr=0 i915.enable_dc=0 nouveau.modeset=0 acpi_backlight=vendor hid_apple.fnmode=1'

# Default packages
declare -a default_packages=(
    "bash-completion"
    "dkms"
    "git"
    "openssh"
    "pciutils"
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

################################################################################
# Logging
################################################################################

installer_log_name="archlinux-installer.log"
installer_log_live="/tmp/${installer_log_name}"
installer_log_installed="/var/log/${installer_log_name}"

log_info() {
    echo -e "[${B}INFO${W}] $*"
}

log_error() {
    echo -e "[${R}ERROR${W}] $*"
}

log_step() {
    echo -e "[${B}INFO${W}] ===== $* ====="
}

_installer_on_error() {
    local exit_code=$?
    set +x
    log_error "Command failed (exit ${exit_code}) at ${BASH_SOURCE[1]:-${0}}:${BASH_LINENO[0]}"
    log_error "Failed command: ${BASH_COMMAND}"
    log_error "Log file: ${INSTALLER_LOGFILE:-${installer_log_live}}"
    persist_installer_log
}

persist_installer_log() {
    local dest_root="${1:-}"
    local src="${INSTALLER_LOGFILE:-${installer_log_live}}"

    sync || true

    if [[ -z "${dest_root}" ]]; then
        # Live ISO with target root mounted; never mkdir /mnt from inside chroot.
        if [[ -d /mnt/boot ]]; then
            dest_root="/mnt"
        else
            return 0
        fi
    fi

    local dest="${dest_root}/var/log/${installer_log_name}"
    mkdir -p "${dest_root}/var/log" || return 0
    [[ -f "${src}" ]] || return 0
    [[ "${src}" == "${dest}" ]] && return 0

    if [[ ! -f "${dest}" ]]; then
        cp -f "${src}" "${dest}" 2>/dev/null || true
    else
        cp -f "${src}" "${dest}.stdout" 2>/dev/null || true
    fi
}

# Capture stdout/stderr on screen + log, and bash xtrace in the log only.
setup_logging() {
    local logfile="${1:-${INSTALLER_LOGFILE:-${installer_log_live}}}"

    mkdir -p "$(dirname "${logfile}")"
    touch "${logfile}"
    export INSTALLER_LOGFILE="${logfile}"

    PS4='+ $(date "+%F %T") ${BASH_SOURCE##*/}:${LINENO} ${FUNCNAME[0]:-main} | '
    export PS4
    exec 3>>"${logfile}"
    export BASH_XTRACEFD=3
    set -x
    set -E

    if [[ "${INSTALLER_LOGGING_TEE:-0}" != "1" ]]; then
        exec > >(tee -a "${logfile}") 2>&1
        export INSTALLER_LOGGING_TEE=1
    fi

    trap '_installer_on_error' ERR
    log_info "Logging to ${logfile} (xtrace in log file only)"
}

# Target /etc/resolv.conf is often a systemd-resolved symlink into /run, which is
# empty in a raw chroot — pacman then cannot fetch core.db / extra.db.
prepare_chroot_network() {
    local root="${1:-/mnt}"

    mkdir -p "${root}/etc"
    rm -f "${root}/etc/resolv.conf"

    if [[ -e /etc/resolv.conf ]] && grep -qE '^\s*nameserver' /etc/resolv.conf 2>/dev/null \
        && ! grep -qE '^\s*nameserver\s+127\.' /etc/resolv.conf; then
        cp -L /etc/resolv.conf "${root}/etc/resolv.conf"
    else
        printf 'nameserver 1.1.1.1\nnameserver 9.9.9.9\nnameserver 8.8.8.8\n' > "${root}/etc/resolv.conf"
    fi
    log_info "Wrote ${root}/etc/resolv.conf for chroot DNS"
}

ensure_pacman_network() {
    if [[ ! -f /etc/resolv.conf ]] || ! grep -qE '^\s*nameserver' /etc/resolv.conf \
        || grep -qE '^\s*nameserver\s+127\.' /etc/resolv.conf; then
        log_info "Fixing DNS resolvers inside chroot"
        printf 'nameserver 1.1.1.1\nnameserver 9.9.9.9\nnameserver 8.8.8.8\n' > /etc/resolv.conf
    fi

    if getent hosts geo.mirror.pkgbuild.com >/dev/null 2>&1 \
        || getent hosts archlinux.org >/dev/null 2>&1; then
        log_info "DNS lookup for Arch mirrors succeeded"
        return 0
    fi

    log_error "No DNS in chroot (cannot resolve Arch mirrors). Live ISO needs working network."
    return 1
}
