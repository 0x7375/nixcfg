{
  flake.modules.nixos.naitoh =
    {
      config,
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
        custom_formats =
          let
            profiles = [
              "Any"
              "HD - 720p/1080p"
              "HD-720p"
              "HD-1080p"
              "Ultra-HD"
            ];
            assign = score: map (name: { inherit name score; }) profiles;
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
        package = pkgs.auto.sonarr;
        config = {
          mediaManagement.autoUnmonitorPreviouslyDownloadedEpisodes = true;
          apiKey._secret = config.sops.secrets."sonarr/api_key".path;
          hostConfig.password._secret = config.sops.secrets."sonarr/pw".path;
        };
      };
    };
}
