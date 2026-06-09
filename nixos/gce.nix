{ lib, modulesPath, ... }: {
  imports = [
    "${toString modulesPath}/virtualisation/google-compute-image.nix"
  ];

  virtualisation.googleComputeImage.diskSize = 20480;

  # the GCE module force-enables OS Login, whose PAM module rejects local
  # users (mcmoodoo) after successful pubkey auth — disable it so the baked-in
  # user + authorized key work like on EC2
  security.googleOsLogin.enable = lib.mkForce false;
}
