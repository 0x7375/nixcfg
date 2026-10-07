{ self, ... }:

{
  flake.modules.darwin.homeVpn =
    { pkgs, ... }:
    {
      packages = [ pkgs.auto.tailscale-gui ];
    };

  flake.modules.nixos.homeVpn =
    { pkgs, config, ... }:
    let
      inherit (config.me) user;
    in
    {
      persist.directories = [ "/var/lib/tailscale" ];

      networking.firewall = {
        trustedInterfaces = [ config.services.tailscale.interfaceName ];
        allowedUDPPorts = [ config.services.tailscale.port ];
      };

      systemd.services.tailscaled.serviceConfig.Environment = [
        "TS_DEBUG_FIREWALL_MODE=nftables"
      ];

      services.tailscale = {
        enable = true;
        package = pkgs.auto.tailscale;
        extraUpFlags = [
          "--operator=${user}"
        ];
      };
    };

  flake.modules.nixos.homeVpnClient = {
    imports = [ self.modules.nixos.homeVpn ];

    networking.firewall.checkReversePath = "loose";

    services.tailscale = {
      useRoutingFeatures = "client";
      extraUpFlags = [ "--accept-routes" ];
    };
  };

  flake.modules.nixos.naitoh =
    { config, ... }:
    {
      imports = [ self.modules.nixos.homeVpn ];

      services.tailscale = {
        useRoutingFeatures = "server";
        extraUpFlags = [
          "--advertise-routes=${config.me.host.ip}/32"
        ];
      };
    };
}
