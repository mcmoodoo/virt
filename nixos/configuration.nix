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

  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  virtualisation.docker.enable = true;

  networking.hostName = "nixos-cloud";

  environment.systemPackages = with pkgs; [
    # core
    git curl wget jq htop
    ripgrep fd fzf bat eza

    # editors
    vim neovim

    # dev
    nodejs pnpm bun
    python311 uv
    rustup
    gcc gnumake

    # infra
    terraform
    docker-compose
  ];

  system.stateVersion = "25.11";
}
