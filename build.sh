#!/bin/bash

set -ouex pipefail

RELEASE="$(rpm -E %fedora)"


# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/39/x86_64/repoview/index.html&protocol=https&redirect=1

#### Install repos
# Bibata cursor theme
curl -o /etc/yum.repos.d/_copr:copr.fedorainfracloud.org:peterwu:rendezvous.repo https://copr.fedorainfracloud.org/coprs/peterwu/rendezvous/repo/fedora-$RELEASE/peterwu-rendezvous-fedora-$RELEASE.repo

# Docker repos
curl -o /etc/yum.repos.d/docker-ce.repo https://download.docker.com/linux/fedora/docker-ce.repo

VIRTUALIZATION="libvirt-daemon-config-network libvirt-daemon-kvm qemu-kvm virt-manager virt-viewer guestfs-tools python3-libguestfs virt-top"
#### Install packages
rpm-ostree override remove vim-data vim-minimal vim-filesystem vim-enhanced vim-common
rpm-ostree install \
	bibata-cursor-themes gnome-tweaks fira-code-fonts keepassxc vlc vlc-plugin-pipewire \
	earlyoom pam-u2f openssl python3-pip rclone plocate \
	fish ripgrep podman-compose neovim go-task bat yubikey-manager fd-find distrobox \
	docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin \
	gnupg2-scdaemon chezmoi age $VIRTUALIZATION \
	postgresql18 # client programs

# gnupg2-scdaemon was removed in f43 - https://discussion.fedoraproject.org/t/gpg-with-yubikeys-on-fedora-43-scdaemon-removed/170981

# ------------ START: INSTALL CUSTOM PROGRAMS ------------
TEMPDIR=`mktemp -d`

cd $TEMPDIR

BINDIR="/usr/bin"

ZELLIJ_VERSION="0.44.3"
curl -LO https://github.com/zellij-org/zellij/releases/download/v$ZELLIJ_VERSION/zellij-x86_64-unknown-linux-musl.tar.gz
tar xzvf zellij-x86_64-unknown-linux-musl.tar.gz
chmod +x ./zellij
mv ./zellij $BINDIR/zellij

AUTORESTIC_VERSION="1.8.3"
curl -LO https://github.com/cupcakearmy/autorestic/releases/download/v$AUTORESTIC_VERSION/autorestic_${AUTORESTIC_VERSION}_linux_amd64.bz2
bzip2 -d autorestic_${AUTORESTIC_VERSION}_linux_amd64.bz2
chmod +x autorestic_${AUTORESTIC_VERSION}_linux_amd64
mv autorestic_${AUTORESTIC_VERSION}_linux_amd64 $BINDIR/autorestic

RESTIC_VERSION="0.18.1"
curl -LO https://github.com/restic/restic/releases/download/v$RESTIC_VERSION/restic_${RESTIC_VERSION}_linux_amd64.bz2
bzip2 -d restic_${RESTIC_VERSION}_linux_amd64.bz2
chmod +x restic_${RESTIC_VERSION}_linux_amd64
mv restic_${RESTIC_VERSION}_linux_amd64 $BINDIR/restic

SYNCTHING_VERSION="2.1.0"
curl -LO https://github.com/syncthing/syncthing/releases/download/v$SYNCTHING_VERSION/syncthing-linux-amd64-v${SYNCTHING_VERSION}.tar.gz
tar -xzvf syncthing-linux-amd64-v${SYNCTHING_VERSION}.tar.gz
mv syncthing-linux-amd64-v${SYNCTHING_VERSION}/syncthing $BINDIR/syncthing
chmod +x $BINDIR/syncthing
mv syncthing-linux-amd64-v${SYNCTHING_VERSION}/etc/linux-desktop/* /usr/share/applications/
mv syncthing-linux-amd64-v${SYNCTHING_VERSION}/etc/linux-systemd/system/syncthing@.service /usr/lib/systemd/system/

ZOXIDE_VERSION="0.9.9"
curl -LO https://github.com/ajeetdsouza/zoxide/releases/download/v${ZOXIDE_VERSION}/zoxide-${ZOXIDE_VERSION}-x86_64-unknown-linux-musl.tar.gz
tar -xzvf zoxide-${ZOXIDE_VERSION}-x86_64-unknown-linux-musl.tar.gz
cp zoxide $BINDIR/zoxide
chmod +x $BINDIR/zoxide

CHEAT_VERSION="5.1.0"
curl -LO https://github.com/cheat/cheat/releases/download/${CHEAT_VERSION}/cheat-linux-amd64.gz
gunzip cheat-linux-amd64.gz
chmod +x cheat-linux-amd64
mv cheat-linux-amd64 $BINDIR/cheat

TLRC_VERSION="1.13.0"
curl -LO https://github.com/tldr-pages/tlrc/releases/download/v${TLRC_VERSION}/tlrc-v${TLRC_VERSION}-x86_64-unknown-linux-musl.tar.gz
tar -xzvf tlrc-v${TLRC_VERSION}-x86_64-unknown-linux-musl.tar.gz
chmod +x tldr
mv tldr $BINDIR/tldr
mv completions/tldr.bash /usr/share/bash-completion/completions/tldr
mv completions/tldr.fish /usr/share/fish/completions/tldr.fish

EZA_VERSION="0.23.4"
curl -LO https://github.com/eza-community/eza/releases/download/v${EZA_VERSION}/eza_x86_64-unknown-linux-gnu.tar.gz
tar -xzvf eza_x86_64-unknown-linux-gnu.tar.gz
chmod +x eza
mv eza $BINDIR/eza

rm -rf $TEMPDIR
# ------------ END: INSTALL CUSTOM PROGRAMS ------------


# ------------ START: INSTALL FIRA CODE NERD FONT ------------
# TEMPDIR=`mktemp -d`
# cd $TEMPDIR
#
# curl -LO https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/FiraMono.zip
# unzip FiraMono.zip
# rm FiraMono.zip
# mkdir -p /usr/local/share/fonts/FiraMono
# cp * /usr/local/share/fonts/FiraMono/
#
# rm -rf $TEMPDIR
#
# fc-cache -fr
# ------------ END: INSTALL FIRA CODE NERD FONT ------------


# ------------ START: SETUP SYMLINKS ------------
ln -fs /usr/bin/go-task /usr/bin/task
ln -fs /usr/bin/nvim /usr/bin/vim
ln -fs /usr/bin/nvim /usr/bin/vi
# ------------ END: SETUP SYMLINKS ------------


# ------------ START: CONFIGURE EDITOR ------------
rm /etc/profile.d/nano-default-editor.sh
rm /etc/profile.d/nano-default-editor.csh

cat <<EOF > /etc/profile.d/nvim-default-editor.sh
# Basically deleted /etc/profile.d/nano-default-editor.csh, but nicer editor
# Ensure NeoVim is set as EDITOR if it isn't already set

if [ -z "\$EDITOR" ]; then
	export EDITOR="/usr/bin/nvim"
fi
EOF

# ------------ END: CONFIGURE EDITOR ------------

#### Systemd

systemctl enable docker

#### Machine-specific bits (Taskfile passes MACHINE=ntb for the laptop image)
if [ "${MACHINE:-}" = "ntb" ]; then
    # Yoga 7i S3 deep sleep: DSDT override packed into the initramfs by dracut
    # via /etc/dracut.conf.d/20-yoga7i-s3.conf, plus a boot-time check that
    # fails when a BIOS update invalidates the baked table
    # (see scripts/dsdt/ in the repo). Requires Secure Boot to stay off.
    cp -a /ntb-rootfs/. /
    systemctl enable dsdt-override-check.service

    # Bake the initramfs into the image. libostree's deploy-time kernel layout
    # pairs the kernel in /usr/lib/modules/<kver> with an initramfs named
    # initramfs.img in the SAME directory, and the base image already ships one
    # there — a copy in /usr/lib/ostree-boot/ would be ignored. Overwrite it
    # here, where the kernel, its config and the ACPI table are all local.
    kver="$(ls -1 /usr/lib/modules | head -n1)"
    dracut --reproducible --add ostree -f "/usr/lib/modules/$kver/initramfs.img" "$kver"
    chmod 0644 "/usr/lib/modules/$kver/initramfs.img"
	
fi
rm -rf /ntb-rootfs

#### Flatpaks - won't install in build-step

# flatpak install -y com.bitwarden.desktop
# flatpak install -y com.github.tchx84.Flatseal
# flatpak install -y org.gnome.seahorse.Application
# flatpak install -y org.signal.Signal
# flatpak install -y com.spotify.Client
# flatpak install -y com.mattjakeman.ExtensionManager
# flatpak install -y md.obsidian.Obsidian
# flatpak install -y org.gnome.NetworkDisplays
#
