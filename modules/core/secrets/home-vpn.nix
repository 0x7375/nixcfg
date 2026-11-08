{ self, ... }:

{
  flake.modules.darwin.homeVpn =
    { mv, ... }:
    {
      packages = [ mv.tip.tailscale-gui ];
    };

  flake.modules.nixos.homeVpn =
    { mv, config, ... }:
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
        package = self.lib.withMainProgram "tailscale" mv.tip.tailscale;
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
      extraSetFlags = [ "--accept-routes" ];
    };
  };

  flake.modules.nixos.naitoh =
    { config, ... }:
    {
      imports = [ self.modules.nixos.homeVpn ];

      services.tailscale = {
        useRoutingFeatures = "server";
        extraSetFlags = [
          "--advertise-routes=${config.me.host.ip}/32"
        ];
      };
    };
}
