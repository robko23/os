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

# Maybe in dev env container: mold 
# https://github.com/Infisical/infisical/releases/download/infisical-cli%2Fv0.31.1/infisical_0.31.1_linux_amd64.rpm
# curl -1sLf 'https://dl.cloudsmith.io/public/infisical/infisical-cli/setup.rpm.sh' | sudo -E bash

#### Install packages
rpm-ostree override remove vim-data vim-minimal vim-filesystem vim-enhanced vim-common
rpm-ostree install \
	bibata-cursor-themes gnome-tweaks fira-code-fonts keepassxc openrgb \
	earlyoom pam-u2f openssl python3-pip rclone \
	fish ripgrep podman-compose neovim go-task eza bat yubikey-manager fd-find distrobox \
	docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# ------------ START: INSTALL CUSTOM PROGRAMS ------------
TEMPDIR=`mktemp -d`

cd $TEMPDIR

BINDIR="/usr/bin"

ZELLIJ_VERSION="0.41.2"
curl -LO https://github.com/zellij-org/zellij/releases/download/v$ZELLIJ_VERSION/zellij-x86_64-unknown-linux-musl.tar.gz
tar xzvf zellij-x86_64-unknown-linux-musl.tar.gz
chmod +x ./zellij
mv ./zellij $BINDIR/zellij

AUTORESTIC_VERSION="1.8.3"
curl -LO https://github.com/cupcakearmy/autorestic/releases/download/v$AUTORESTIC_VERSION/autorestic_${AUTORESTIC_VERSION}_linux_amd64.bz2
bzip2 -d autorestic_${AUTORESTIC_VERSION}_linux_amd64.bz2
chmod +x autorestic_${AUTORESTIC_VERSION}_linux_amd64
mv autorestic_${AUTORESTIC_VERSION}_linux_amd64 $BINDIR/autorestic

RESTIC_VERSION="0.17.3"
curl -LO https://github.com/restic/restic/releases/download/v$RESTIC_VERSION/restic_${RESTIC_VERSION}_linux_amd64.bz2
bzip2 -d restic_${RESTIC_VERSION}_linux_amd64.bz2
chmod +x restic_${RESTIC_VERSION}_linux_amd64
mv restic_${RESTIC_VERSION}_linux_amd64 $BINDIR/restic

SYNCTHING_VERSION="1.28.1"
curl -LO https://github.com/syncthing/syncthing/releases/download/v$SYNCTHING_VERSION/syncthing-linux-amd64-v${SYNCTHING_VERSION}.tar.gz
tar -xzvf syncthing-linux-amd64-v${SYNCTHING_VERSION}.tar.gz
mv syncthing-linux-amd64-v${SYNCTHING_VERSION}/syncthing $BINDIR/syncthing
chmod +x $BINDIR/syncthing
mv syncthing-linux-amd64-v${SYNCTHING_VERSION}/etc/linux-desktop/* /usr/share/applications/
mv syncthing-linux-amd64-v${SYNCTHING_VERSION}/etc/linux-systemd/system/syncthing@.service /usr/lib/systemd/system/

ZOXIDE_VERSION="0.9.6"
curl -LO https://github.com/ajeetdsouza/zoxide/releases/download/v${ZOXIDE_VERSION}/zoxide-${ZOXIDE_VERSION}-x86_64-unknown-linux-musl.tar.gz
tar -xzvf zoxide-${ZOXIDE_VERSION}-x86_64-unknown-linux-musl.tar.gz
cp zoxide $BINDIR/zoxide
chmod +x $BINDIR/zoxide

CHEAT_VERSION="4.4.2"
curl -LO https://github.com/cheat/cheat/releases/download/${CHEAT_VERSION}/cheat-linux-amd64.gz
gunzip cheat-linux-amd64.gz
chmod +x cheat-linux-amd64
mv cheat-linux-amd64 $BINDIR/cheat

TLRC_VERSION="1.9.3"
curl -LO https://github.com/tldr-pages/tlrc/releases/download/v${TLRC_VERSION}/tlrc-v${TLRC_VERSION}-x86_64-unknown-linux-musl.tar.gz
tar -xzvf tlrc-v${TLRC_VERSION}-x86_64-unknown-linux-musl.tar.gz
chmod +x tldr
mv tldr $BINDIR/tldr
mv completions/tldr.bash /usr/share/bash-completion/completions/tldr
mv completions/tldr.fish /usr/share/fish/completions/tldr.fish

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
ln -s /usr/bin/go-task /usr/bin/task
ln -s /usr/bin/nvim /usr/bin/vim
ln -s /usr/bin/nvim /usr/bin/vi
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
