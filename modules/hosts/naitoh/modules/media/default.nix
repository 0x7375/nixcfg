{ self, ... }:

{
  flake.modules.nixos.naitoh =
    {
      config,
      mv,
      pkgs,
      lib,
      ...
    }:
    {
      options.me = {
        blocklistId = lib.mkOption {
          type = lib.types.str;
          default = "b90c2a8f113e4b7b9f3d53b2169824de";
        };

        mediaGroup = lib.mkOption {
          type = lib.types.str;
          default = "media";
          description = "Media group name";
          internal = true;
        };
      };

      config = {
        services.recyclarr.package = self.lib.withMainProgram "recyclarr" mv.tip.recyclarr;

        nixflix = {
          enable = true;
          mediaDir = "/data/shared/media";
          downloadsDir = "/data/shared/downloads";
          stateDir = "/data/main/.state";
          postgres.enable = true;
          recyclarr.enable = true;
        };

        systemd.tmpfiles.settings."arr-media" =
          let
            mkDir = user: {
              inherit user;
              group = "media";
              mode = "02775";
            };

            mkMediaDirs = base: {
              "${base}/media".d = mkDir "root";
              "${base}/media/movies".d = mkDir "radarr";
              "${base}/media/tv".d = mkDir "sonarr";
              "${base}/downloads/torrent".d = mkDir "qbittorrent";
              "${base}/downloads/torrent/default".d = mkDir "qbittorrent";
              "${base}/downloads/torrent/prowlarr".d = mkDir "qbittorrent";
              "${base}/downloads/torrent/radarr".d = mkDir "qbittorrent";
              "${base}/downloads/torrent/sonarr".d = mkDir "qbittorrent";
            };
          in
          mkMediaDirs "/mnt/ssd" // mkMediaDirs "/mnt/hdd" // mkMediaDirs "/mnt/nvme";

        systemd.tmpfiles.rules =
          let
            personalBlocklistFile = pkgs.writeText "personal-blocklist.json" (
              builtins.toJSON {
                trash_id = config.me.blocklistId;
                trash_scores = {
                  default = -10000;
                };
                name = "Personal Blocklist";
                includeCustomFormatWhenRenaming = false;
                specifications = [
                  {
                    name = "Blacklisted Groups Regex";
                    implementation = "ReleaseTitleSpecification";
                    negate = false;
                    required = true;
                    fields.value = "\\b(y2flix|nextbadgrouptoblacklist)\\b";
                  }
                ];
              }
            );

            settingsYml =
              pkgs.writeText "settings.yml"
                # yaml
                ''
                  resource_providers:
                    - name: local-sonarr-formats
                      type: custom-formats
                      path: /var/lib/recyclarr/custom_formats
                      service: sonarr
                    - name: local-radarr-formats
                      type: custom-formats
                      path: /var/lib/recyclarr/custom_formats
                      service: radarr
                '';
          in
          [
            "d /var/lib/recyclarr/custom_formats 0755 recyclarr recyclarr - -"
            "L+ /var/lib/recyclarr/custom_formats/personal-blocklist.json 0644 recyclarr recyclarr - ${personalBlocklistFile}"
            "L+ /var/lib/recyclarr/settings.yml 0644 recyclarr recyclarr - ${settingsYml}"
          ];

        systemd.services = lib.mkMerge (
          map (service: self.lib.notifyOnServiceFailure service) [
            "podman-cleanuparr"
            "jellyfin"
            "syncthing"
            "seerr"
            "prowlarr"
            "flaresolverr"
            "qbittorrent"
            "qui"
            "radarr"
            "sonarr"
            "bazarr"
            "recylarr"
            "attic"
            "sshd"
            "beszel-agent"
            "beszel-hub"
          ]
        );
      };
    };
}
