{ self, ... }:

{
  flake.modules.nixos.naitoh =
    {
      config,
      mv,
      ...
    }:
    {
      me.services.autobrr = {
        subdomain = "auto";
        inherit (config.services.autobrr.settings) port;
      };

      me.hostSecrets.autobrr_session.owner = config.services.qbittorrent.user;

      persist.directories = [
        {
          directory = "/var/lib/private/autobrr";
          user = "nobody";
          group = "nogroup";
          mode = "0755";
        }
      ];

      services.autobrr = {
        enable = true;
        openFirewall = true;
        package = self.lib.withMainProgram "autobrr" mv.latest.autobrr;
        secretFile = config.sops.secrets.autobrr_session.path;
        settings = {
          host = "127.0.0.1";
          checkForUpdates = false;
        };
      };
    };
}
