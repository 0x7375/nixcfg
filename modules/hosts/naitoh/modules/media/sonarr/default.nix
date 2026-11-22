{
  flake.modules.nixos.naitoh =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      me.services.sonarr = {
        subdomain = "shows";
        port = config.nixflix.sonarr.config.hostConfig.port;
      };

      me.hostSecrets."sonarr/api_key" = { };
      me.hostSecrets."sonarr/pw" = { };

      nixflix.recyclarr.config.sonarr.sonarr = {
        media_naming.episodes.rename = true;

        quality_profiles = lib.mkForce [
          {
            name = "KHALITE";
            min_format_score = 0;
            reset_unmatched_scores.enabled = true;

            upgrade = {
              allowed = false;
              until_quality = "Bluray-1080p Remux";
            };

            qualities = map (name: { inherit name; }) [
              "WEBDL-1080p"
              "Bluray-1080p"
              "HDTV-1080p"
              "Bluray-1080p Remux"
              "WEBDL-2160p"
              "Bluray-2160p"
              "HDTV-2160p"
              "Bluray-2160p Remux"
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
              trash_ids = [ "ae575f95ab639ba5d15f663bf019e3e8" ];
              assign_scores_to = assign (-10000);
            }
            # Season Packs
            {
              trash_ids = [ "3bc5f395426614e155e585a2f056cdf1" ];
              assign_scores_to = assign 1000;
            }
            # Blacklisted group
            {
              trash_ids = [ config.me.blocklistId ];
              assign_scores_to = assign (-10000);
            }
            # Block Dolby Vision Profile 5 (No HDR fallback)
            {
              trash_ids = [ "9b27ab6498ec0f31a3353992e19434ca" ];
              assign_scores_to = assign (-10000);
            }
          ];
      };

      nixflix.sonarr = {
        enable = true;
        openFirewall = true;
        package = pkgs.callPackage ./_package.nix { };
        config = {
          mediaManagement.autoUnmonitorPreviouslyDownloadedEpisodes = true;
          apiKey._secret = config.sops.secrets."sonarr/api_key".path;
          hostConfig.password._secret = config.sops.secrets."sonarr/pw".path;
        };
      };
    };
}
