{ modulesPath, ... }: {
  imports = [
    "${toString modulesPath}/virtualisation/google-compute-image.nix"
  ];

  virtualisation.googleComputeImage.diskSize = 20480;
}
