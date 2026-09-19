#!/bin/bash
################################################################################
# Author  : David Calvert
# Purpose : Arch Linux custom desktop post-installer
# GitHub  : https://github.com/dotdc/archlinux-installer
################################################################################

set -e

################################################################################
# Source variables
################################################################################

. config-variables.sh
setup_logging "${INSTALLER_LOGFILE:-${installer_log_installed}}"

################################################################################
# Desktop Post-install
################################################################################


# Install all packages 
echo -e "[${B}INFO${W}] Install desktop ${Y}pacman${W} packages"
pacman -Sy --noconfirm --needed --color auto  "${desktop_packages[@]}"


# Install yay
echo -e "[${B}INFO${W}] Install ${Y}yay${W}"
cd /tmp
git clone https://aur.archlinux.org/yay.git
cd yay
chown -R ${username}: .
sudo -u ${username} makepkg -si --noconfirm

# Install AUR Packages
echo -e "[${B}INFO${W}] Install ${Y}AUR${W} packages"
sudo -u ${username} yay -Sy --noconfirm --color auto "${aur_packages[@]}"

# GDM: prefer GNOME on Wayland (Xorg session remains available)
echo -e "[${B}INFO${W}] Configure GDM for Wayland"
if [[ -f /etc/gdm/custom.conf ]] ; then
    sed -i 's/^#WaylandEnable=.*/WaylandEnable=true/' /etc/gdm/custom.conf
    sed -i 's/^WaylandEnable=.*/WaylandEnable=true/' /etc/gdm/custom.conf
    if ! grep -q '^WaylandEnable=' /etc/gdm/custom.conf ; then
        sed -i '/^\[daemon\]/a WaylandEnable=true' /etc/gdm/custom.conf
    fi
    if ! grep -q '^DefaultSession=' /etc/gdm/custom.conf ; then
        sed -i '/^\[daemon\]/a DefaultSession=gnome.desktop' /etc/gdm/custom.conf
    fi
else
    mkdir -p /etc/gdm
    cat > /etc/gdm/custom.conf << 'EOF'
[daemon]
WaylandEnable=true
DefaultSession=gnome.desktop
EOF
fi

cat >> /etc/environment << 'EOF'
MOZ_ENABLE_WAYLAND=1
ELECTRON_OZONE_PLATFORM_HINT=wayland
EOF

# Start services
echo -e "[${B}INFO${W}] Enable systemctl services"
systemctl enable gdm
systemctl enable NetworkManager
systemctl enable bluetooth
systemctl enable docker
systemctl enable cups

# Set Gnome default favorites apps
mkdir -p /etc/dconf/profile
mkdir -p /etc/dconf/db/local.d
echo -e "user-db:user
system-db:local" > /etc/dconf/profile/user
echo -e "# Set Gnome default favorites apps
# To find apps:
# find / -iname \"*desktop\" -type f -not -path \"/media*\" 2> /dev/null
[org/gnome/shell]
favorite-apps = ${favorite_apps}

[org/gnome/desktop/input-sources]
sources = [('xkb', '${xkb_layout}')]

[org/gnome/desktop/interface]
clock-format = '24h'
" > /etc/dconf/db/local.d/00-favorite-apps
dconf update

# Install dotfiles for user
mkdir -p /home/${username}/Documents/workspace/repos/
cd /home/${username}/Documents/workspace/repos/
git clone https://github.com/dotdc/dotfiles
cd dotfiles
su ${username} -c "make all"
chown -R ${username}: /home/${username}

# Reboot
echo -e "[${B}INFO${W}] Post-install complete!"
echo -e "[${B}INFO${W}] Type ${Y}CTRL+D${W} and ${Y}reboot${W} to reboot in Arch!"
