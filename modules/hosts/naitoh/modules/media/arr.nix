{ self, ... }:

{
  flake.modules.nixos.naitoh =
    {
      config,
      mv,
      lib,
      ...
    }:
    let
      profile = "KHALITE";

      mkFormat = id: score: {
        trash_ids = [ id ];
        assign_scores_to = [
          {
            name = profile;
            inherit score;
          }
        ];
      };

      apps = {
        sonarr = {
          subdomain = "shows";
          mainProgram = "Sonarr";
          clientId = "464aab45-7fa4-4f60-bc6c-054834f7f409";

          mediaType = "episodes";
          unmonitorOption = "autoUnmonitorPreviouslyDownloadedEpisodes";

          remux = resolution: "Bluray-${resolution} Remux";
          untilQuality = "Bluray-1080p Remux";

          customFormats = [
            # Not original language
            (mkFormat "ae575f95ab639ba5d15f663bf019e3e8" (-10000))
            # Season Packs
            (mkFormat "3bc5f395426614e155e585a2f056cdf1" 1000)
            # Blacklisted group
            (mkFormat config.me.blocklistId (-10000))
            # Block Dolby Vision Profile 5
            (mkFormat "9b27ab6498ec0f31a3353992e19434ca" (-10000))
          ];
        };

        radarr = {
          subdomain = "movies";
          mainProgram = "Radarr";
          clientId = "871996dd-fe43-4905-a305-4c1151786107";

          mediaType = "movie";
          unmonitorOption = "autoUnmonitorPreviouslyDownloadedMovies";

          remux = resolution: "Remux-${resolution}";
          untilQuality = "WEBDL-1080p";

          customFormats = [
            # Not original language
            (mkFormat "d6e9318c875905d6cfb5bee961afcea9" (-10000))
            # Blacklisted group
            (mkFormat config.me.blocklistId (-10000))
            # Block Dolby Vision Profile 5
            (mkFormat "923b6abef9b17f937fab56cfcf89e1f1" (-10000))
          ];
        };
      };
    in
    {
      me.services = lib.mapAttrs (name: app: {
        inherit (app) subdomain;
        inherit (config.nixflix.${name}.config.hostConfig) port;
        webSockets = true;

        extraConfig = ''
          proxy_buffer_size 16k;
          proxy_buffers 8 16k;
        '';
      }) apps;

      me.hostSecrets = lib.genAttrs (lib.concatMap (name: [
        "${name}/api_key"
        "oidc/${name}"
      ]) (builtins.attrNames apps)) (_: { });

      nixflix =
        lib.mapAttrs (name: app: {
          enable = true;
          package = self.lib.withMainProgram app.mainProgram mv.latest.${name};

          config = {
            mediaManagement.${app.unmonitorOption} = true;
            apiKey._secret = config.sops.secrets."${name}/api_key".path;

            hostConfig = {
              authenticationMethod = "oidc";
              authenticationRequired = "enabled";
              trustedNetworks = "127.0.0.1/32";

              username = null;
              password = null;

              oidc = {
                authority = config.me.services.pocket-id.url;
                inherit (app) clientId;
                clientSecret._secret = config.sops.secrets."oidc/${name}".path;
                userIdentifier = config.me.oidcSubject;
                scopes = "openid profile";
              };
            };
          };
        }) apps
        // {
          recyclarr.config = lib.mapAttrs (name: app: {
            ${name} = {
              media_naming.${app.mediaType}.rename = true;

              quality_profiles = lib.mkForce [
                {
                  name = profile;
                  min_format_score = 0;
                  reset_unmatched_scores.enabled = true;

                  upgrade = {
                    allowed = false;
                    until_quality = app.untilQuality;
                  };

                  qualities = map (name: { inherit name; }) (
                    lib.concatMap
                      (resolution: [
                        "WEBDL-${resolution}"
                        "Bluray-${resolution}"
                        "HDTV-${resolution}"
                        (app.remux resolution)
                      ])
                      [
                        "1080p"
                        "2160p"
                      ]
                  );
                }
              ];

              custom_formats = app.customFormats;
            };
          }) apps;
        };
    };
}
