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

      me.hostSecrets."oidc/autobrr" = { };

      services.autobrr = {
        enable = true;
        package = self.lib.withMainProgram "autobrr" mv.latest.autobrr;
        secretFile = config.sops.secrets.autobrr_session.path;
        settings = {
          host = "127.0.0.1";
          checkForUpdates = false;

          oidcEnabled = true;
          oidcIssuer = config.me.services.pocket-id.url;
          oidcClientId = "3d295157-bde9-4e90-812b-0db34ebae84f";
          oidcRedirectUrl = "${config.me.services.autobrr.url}/api/auth/oidc/callback";
          oidcDisableBuiltInLogin = true;
          oidcAutoRedirect = true;
        };
      };

      systemd.services.autobrr = {
        serviceConfig.LoadCredential = [
          "oidc-secret:${config.sops.secrets."oidc/autobrr".path}"
        ];

        environment = {
          AUTOBRR__OIDC_CLIENT_SECRET_FILE = "%d/oidc-secret";
          AUTOBRR__OIDC_ALLOWED_SUBJECT = config.me.oidcSubject;
        };
      };
    };
}
