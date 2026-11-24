{
  flake.modules.nixos.naitoh =
    { config, pkgs, ... }:
    {
      me.services.graine = {
        subdomain = "graine";
        port = 3000;
      };

      virtualisation.oci-containers.containers.graine =
        let
          name = "ghcr.io/0x7375/graine";
          version = "latest";
        in
        {
          image = name + ":" + version;

          imageFile = pkgs.dockerTools.pullImage {
            imageName = name;
            imageDigest = "sha256:d1cfbe646ac04c1e502b7710d8c88c7016ba743fc21f856eb5732720750cb256";
            sha256 = "sha256-sNpHfxrP2nq0YgyivG/mSGbKuTGEvY0mpzhWLgAk9V4=";

            finalImageTag = version;
          };

          extraOptions = [ "--network=host" ];

          volumes =
            let
              graineConfig = (pkgs.formats.toml { }).generate "graine.toml" {
                url = "http://127.0.0.1:${toString config.nixflix.torrentClients.qbittorrent.webuiPort}";
                disk_path = "/data/shared";
                high_watermark = 0.85;
                low_watermark = 0.82;
                grace_days = 7;

                listen = "127.0.0.1:3000";
                interval_seconds = 3600;
                web_dir = "/opt/graine/web";
                password_file = "/run/secrets/qbittorrent-pw";

                managed_categories = [
                  "autobrr"
                  "sonarr"
                  "radarr"
                ];

                trackers = [
                  {
                    name = "V3X";
                    hosts = [
                      "tk.v3x.tw"
                      "announce.v3x.club"
                    ];
                    priority = 10;
                  }
                  {
                    name = "C411";
                    hosts = [
                      "c411.org"
                      "tk.c411.tw"
                    ];
                    priority = 10;
                  }
                  {
                    name = "TR4KER";
                    hosts = [ "tk.tr4ker.net" ];
                    priority = 10;
                  }
                  {
                    name = "SPEEDAPP";
                    hosts = [
                      "ramjet.speedapp.io"
                      "ramjet.speedapp.to"
                      "ramjet.speedappio.org"
                    ];
                    priority = 10;
                  }
                ];
              };
            in
            [
              "${graineConfig}:/etc/graine/config.toml:ro"
              "${config.sops.secrets."qbittorrent/pw".path}:/run/secrets/qbittorrent-pw:ro"
              "/var/lib/graine:/var/lib/graine"
              "/data/shared:/data/shared:ro"
            ];
        };

      systemd.tmpfiles.rules = [
        "d /var/lib/graine 0700 root root - -"
      ];

      persist.directories = [
        "/var/lib/graine"
      ];
    };
}
