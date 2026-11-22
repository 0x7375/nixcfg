{ self, ... }:

{
  flake.modules.nixos.naitoh =
    {
      config,
      mv,
      lib,
      ...
    }:
    {
      me.services.radarr = {
        subdomain = "movies";
        port = config.nixflix.radarr.config.hostConfig.port;
      };

      me.hostSecrets."radarr/api_key" = { };
      me.hostSecrets."radarr/pw" = { };

      nixflix.recyclarr.config.radarr.radarr = {
        media_naming.movie.rename = true;

        quality_profiles = lib.mkForce [
          {
            name = "KHALITE";
            min_format_score = 0;
            reset_unmatched_scores.enabled = true;

            upgrade = {
              allowed = false;
              until_quality = "WEBDL-1080p";
            };

            qualities = map (name: { inherit name; }) [
              "WEBDL-1080p"
              "Bluray-1080p"
              "HDTV-1080p"
              "Remux-1080p"
              "WEBDL-2160p"
              "Bluray-2160p"
              "HDTV-2160p"
              "Remux-2160p"
            ];
          }
        ];

        custom_formats =
          let
            assign = score: [
              {
                name = "KHALITE";
                inherit score;
              }
            ];
          in
          [
            # Not original language
            {
              trash_ids = [ "d6e9318c875905d6cfb5bee961afcea9" ];
              assign_scores_to = assign (-10000);
            }
            # Blacklisted group
            {
              trash_ids = [ config.me.blocklistId ];
              assign_scores_to = assign (-10000);
            }
            # Block Dolby Vision Profile 5 (No HDR fallback)
            {
              trash_ids = [ "923b6abef9b17f937fab56cfcf89e1f1" ];
              assign_scores_to = assign (-10000);
            }
          ];
      };

      nixflix.radarr = {
        enable = true;
        openFirewall = true;
        package = self.lib.withMainProgram "Radarr" mv.latest.radarr;
        config = {
          mediaManagement.autoUnmonitorPreviouslyDownloadedMovies = true;
          apiKey._secret = config.sops.secrets."radarr/api_key".path;
          hostConfig.password._secret = config.sops.secrets."radarr/pw".path;
        };
      };
    };
}
