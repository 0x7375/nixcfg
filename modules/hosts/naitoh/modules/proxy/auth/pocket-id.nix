{ self, ... }:

{
  flake.modules.nixos.naitoh =
    {
      mv,
      lib,
      config,
      ...
    }:
    {
      options.me.oidcSubject = lib.mkOption {
        type = lib.types.str;
        default = "9390fece-d8a0-40d1-a176-d8813e991a08";
        description = "Pocket ID user subject identifier";
      };

      config = {
        me.services.pocket-id = {
          subdomain = "id";
          port = 1411;

          extraConfig = ''
            proxy_buffer_size 16k;
            proxy_buffers 8 16k;
          '';
        };

        me.hostSecrets."pocket-id/encryption_key" = { };

        services.pocket-id = {
          enable = true;
          package = self.lib.withMainProgram "pocket-id" mv.latest.pocket-id;
          credentials.ENCRYPTION_KEY = config.sops.secrets."pocket-id/encryption_key".path;
          settings = {
            APP_URL = config.me.services.pocket-id.url;
            HOST = "127.0.0.1";
            PORT = 1411;
            TRUST_PROXY = true;
            ANALYTICS_DISABLED = true;
            ALLOW_INSECURE_CALLBACK_URLS = false;
            DISABLE_RATE_LIMITING = true;

            UI_CONFIG_DISABLED = true;
            REQUIRE_USER_EMAIL = true;
            ALLOW_USER_SIGNUPS = "withToken";
            SIGNUP_DEFAULT_USER_GROUP_IDS = builtins.toJSON [
              "a53e501d-2f5f-45df-99bf-17c093a6e243"
            ];
          };
        };

        persist.directories = [
          {
            directory = config.services.pocket-id.dataDir;
            inherit (config.services.pocket-id) user group;
            mode = "0700";
          }
        ];

        systemd.services = self.lib.notifyOnServiceFailure "pocket-id";
      };
    };
}
