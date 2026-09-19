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

################################################################################
# Desktop Post-install
################################################################################


# Install all packages (GNOME; keep X.Org server out of the install)
echo -e "[${B}INFO${W}] Install desktop ${Y}pacman${W} packages"
pacman -Sy --color auto --ignore xorg-server --ignore xorg-server-common "${desktop_packages[@]}"

# Drop X11 display server if a dependency pulled it in anyway
if pacman -Qq xorg-server >/dev/null 2>&1 ; then
    echo -e "[${B}INFO${W}] Removing ${Y}xorg-server${W} (Wayland-only GNOME)"
    pacman -Rdd --noconfirm xorg-server xorg-server-common || true
fi

# Install yay
echo -e "[${B}INFO${W}] Install ${Y}yay${W}"
cd /tmp
git clone https://aur.archlinux.org/yay.git
cd yay
chown -R ${username}: .
sudo -u ${username} makepkg -si

# Install AUR Packages
echo -e "[${B}INFO${W}] Install ${Y}AUR${W} packages"
sudo -u ${username} yay -Sy --color auto "${aur_packages[@]}"

# GDM: Wayland GNOME only (no X11 session)
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

if [[ -d /usr/share/xsessions ]] ; then
    for session in /usr/share/xsessions/*.desktop ; do
        [[ -f "${session}" ]] && printf '\nHidden=true\n' >> "${session}"
    done
fi

cat >> /etc/environment << 'EOF'
MOZ_ENABLE_WAYLAND=1
ELECTRON_OZONE_PLATFORM_HINT=wayland
QT_QPA_PLATFORM=wayland
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
