{ self, ... }:

{
  flake.modules.nixos.naitoh =
    {
      config,
      mv,
      ...
    }:
    {
      me.services.seerr = {
        subdomain = "request";
        port = config.nixflix.seerr.port;
      };

      me.hostSecrets."seerr/api_key" = { };

      systemd.services.seerr-jellyfin = {
        after = [ "jellyfin.service" ];
        requires = [ "jellyfin.service" ];
      };

      nixflix.seerr = {
        enable = true;
        package = self.lib.withMainProgram "seerr" mv.latest.seerr;
        openFirewall = true;
        apiKey._secret = config.sops.secrets."seerr/api_key".path;
      };
    };
}
