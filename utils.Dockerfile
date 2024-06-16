FROM registry.fedoraproject.org/fedora-toolbox:40

RUN dnf install -y xca fuse-libs fuse3-libs neovim ranger ripgrep qt5-qtbase-postgresql 
