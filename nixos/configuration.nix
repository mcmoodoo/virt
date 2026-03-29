{ config, pkgs, ... }: {
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAfykrd69s822j0/pQamj0yncMODffsMXghBfWOB/qjc mcmoodoo@brine"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  networking.hostName = "nixos-cloud";

  environment.systemPackages = with pkgs; [
    jq
    vim
    htop
    git
    curl
  ];

  system.stateVersion = "25.11";
}
