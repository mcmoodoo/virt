{ config, pkgs, ... }: {
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "mcmoodoo" ];
  };

  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (pkg.pname or (builtins.parseDrvName pkg.name).name) [
      "terraform"
    ];

  users.users.mcmoodoo = {
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

  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      stdenv.cc.cc.lib
    ];
  };

  environment.sessionVariables.LD_LIBRARY_PATH = [ "${pkgs.stdenv.cc.cc.lib}/lib" ];
  virtualisation.docker.enable = true;

  networking.hostName = "nixos-cloud";
  networking.firewall.enable = false;

  systemd.services.bootstrap-dotfiles = {
    description = "Clone mcmoodoo/dotfiles and stow on first boot";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    unitConfig.ConditionPathExists = "!/home/mcmoodoo/dotfiles";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "mcmoodoo";
      Group = "users";
      WorkingDirectory = "/home/mcmoodoo";
    };
    path = with pkgs; [ git stow ];
    script = ''
      mkdir -p /home/mcmoodoo/.config
      git clone https://github.com/mcmoodoo/dotfiles.git /home/mcmoodoo/dotfiles
      cd /home/mcmoodoo/dotfiles
      stow nvim bash starship
    '';
  };

  systemd.services.bootstrap-claude-code = {
    description = "Install Claude Code CLI on first boot (runs in background)";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    unitConfig.ConditionPathExists = "!/home/mcmoodoo/.local/bin/claude";
    serviceConfig = {
      Type = "oneshot";
      User = "mcmoodoo";
      Group = "users";
      WorkingDirectory = "/home/mcmoodoo";
    };
    path = with pkgs; [ curl bash cacert ];
    script = ''
      curl -fsSL https://claude.ai/install.sh | bash
    '';
  };

  systemd.services.bootstrap-nvim-plugins = {
    description = "Pre-install nvim plugins via lazy.nvim (runs in background)";
    wantedBy = [ "multi-user.target" ];
    after = [ "bootstrap-dotfiles.service" ];
    requires = [ "bootstrap-dotfiles.service" ];
    unitConfig.ConditionPathExists = "!/home/mcmoodoo/.local/share/nvim/lazy/lazy.nvim";
    serviceConfig = {
      Type = "oneshot";
      User = "mcmoodoo";
      Group = "users";
      WorkingDirectory = "/home/mcmoodoo";
    };
    path = with pkgs; [ neovim git ];
    script = ''
      nvim --headless "+Lazy! sync" +qa
    '';
  };

  environment.systemPackages = with pkgs; [
    sqlite
    age
    tree
    pinentry-curses
    dig
    s3fs
    rclone
    goofys
    awscli2
    git
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
    just
    qrencode
  ];

  system.stateVersion = "25.11";
}
