{
  flake.modules.nixos.naitoh =
    {
      config,
      pkgs,
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
        package = pkgs.auto.radarr;
        config = {
          mediaManagement.autoUnmonitorPreviouslyDownloadedMovies = true;
          apiKey._secret = config.sops.secrets."radarr/api_key".path;
          hostConfig.password._secret = config.sops.secrets."radarr/pw".path;
        };
      };
    };
}
