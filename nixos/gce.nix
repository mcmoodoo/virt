{ lib, modulesPath, ... }: {
  imports = [
    "${toString modulesPath}/virtualisation/google-compute-image.nix"
  ];

  virtualisation.googleComputeImage.diskSize = 20480;

  # the GCE module force-enables OS Login, whose PAM module rejects local
  # users (mcmoodoo) after successful pubkey auth — disable it so the baked-in
  # user + authorized key work like on EC2
  security.googleOsLogin.enable = lib.mkForce false;

  # On GCE, DNS is served by the metadata server at 169.254.169.254, reached
  # on-link via eth0 (which only has a /32 address). NixOS's default dhcpcd
  # deny-list does not exclude docker's veth interfaces, so dhcpcd runs IPv4LL
  # (zeroconf) on them, assigns each a 169.254.x.x/16 address, and installs a
  # 169.254.0.0/16 link route per veth. Those routes shadow the path to the
  # metadata DNS server, so all name resolution breaks once docker starts —
  # raw IP connectivity (e.g. 8.8.8.8) still works, which is the tell.
  #
  # Disable IPv4LL globally (eth0 always gets a real DHCP lease here, so the
  # zeroconf fallback is never needed) so no interface grabs a 169.254 address,
  # and pin an explicit on-link route to the metadata server via eth0 as a
  # defensive backstop.
  networking.dhcpcd.extraConfig = "noipv4ll";

  networking.interfaces.eth0.ipv4.routes = [
    { address = "169.254.169.254"; prefixLength = 32; }
  ];
}
