{ config, pkgs, ... }: {
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (pkg.pname or (builtins.parseDrvName pkg.name).name) [
      "terraform"
    ];

  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" "docker" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBNa7ESvNH13xd7nIqrU/U6eQCDyOPIZ09UmMGx6XbE+ local vm"
    ];
  };

  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_16;

    extensions = with pkgs.postgresql16Packages; [
      pgvector
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  programs.nix-ld.enable = true;
  virtualisation.docker.enable = true;

  networking.hostName = "nixos-cloud";

  environment.systemPackages = with pkgs; [
    sqlite
    postgresql
    age
    tree
    pinentry-curses
    dig
    s3fs
    rclone
    goofys
    awscli2
    gh
    lazygit
    lazydocker
    lazyjournal
    gitleaks
    trufflehog
    detect-secrets
    shellcheck
    semgrep
    rsync
    aria2
    wget
    curl
    xh
    restish
    atac
    superfile
    nnn
    vifm
    vim
    neovim
    eza
    bun
    nodejs_24
    pnpm
    openssl
    pass
    ncdu
    libzip
    unzip
    fastfetch
    mermaid-cli
    nix-index
    stow
    starship
    gcc
    gnumake
    lua
    luarocks-nix
    rustup
    python314 uv
    lld
    ydiff
    diff-so-fancy
    delta
    broot
    fzf
    file
    bottom
    fd
    bat
    html-tidy
    envsubst
    yq-go
    jq
    fx
    ripgrep
    zoxide
    w3m
    zellij
    firejail
    just
    resvg
    qrencode
    asciinema_3
    asciinema-agg
  ];

  system.stateVersion = "25.11";
}
