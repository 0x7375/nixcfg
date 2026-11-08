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

      persist.directories = [ "/var/lib/private/autobrr" ];

      services.autobrr = {
        enable = true;
        openFirewall = true;
        package = self.lib.withMainProgram "autobrr" mv.tip.autobrr;
        secretFile = config.sops.secrets.autobrr_session.path;
        settings = {
          host = "0.0.0.0";
          checkForUpdates = false;
        };
      };
    };
}
