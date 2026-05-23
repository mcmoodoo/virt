{ modulesPath, lib, ... }: {
  imports = [
    "${toString modulesPath}/../maintainers/scripts/ec2/amazon-image.nix"
  ];

  virtualisation.diskSize = 20480;

  services.openssh.settings.PermitRootLogin = lib.mkForce "no";
}
