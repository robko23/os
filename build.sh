#!/bin/bash

set -ouex pipefail

RELEASE="$(rpm -E %fedora)"


### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/39/x86_64/repoview/index.html&protocol=https&redirect=1

curl -o /etc/yum.repos.d/_copr:copr.fedorainfracloud.org:peterwu:rendezvous.repo https://copr.fedorainfracloud.org/coprs/peterwu/rendezvous/repo/fedora-$RELEASE/peterwu-rendezvous-fedora-$RELEASE.repo

rpm-ostree override remove vim-data vim-minimal vim-filesystem vim-enhanced vim-common
rpm-ostree install fish ripgrep ranger podman-compose neovim buildah bibata-cursor-themes evolution evolution-ews

curl -o /tmp/zellij https://github.com/zellij-org/zellij/releases/download/v0.40.1/zellij-x86_64-unknown-linux-musl.tar.gz
mv /tmp/zellij /usr/local/bin/zellij

#### Example for enabling a System Unit File

# systemctl enable podman.socket


flatpak install -y com.bitwarden.desktop
flatpak install -y com.github.tchx84.Flatseal
flatpak install -y org.gnome.seahorse.Application
flatpak install -y org.signal.Signal
flatpak install -y com.spotify.Client
flatpak install -y com.github.GradienceTeam.Gradience
