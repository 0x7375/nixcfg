{
  flake.modules.nixos.naitoh =
    {
      config,
      pkgs,
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
        package = pkgs.auto.autobrr;
        secretFile = config.sops.secrets.autobrr_session.path;
        settings = {
          host = "0.0.0.0";
          checkForUpdates = false;
        };
      };
    };
}
