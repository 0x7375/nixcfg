{ inputs, ... }:

{
  flake.modules.nixos.naitoh =
    {
      config,
      pkgs,
      ...
    }:

    let
      graine = inputs.graine.packages.${pkgs.stdenv.hostPlatform.system}.default;

      graineConfig = (pkgs.formats.toml { }).generate "graine.toml" {
        url = "http://localhost:${toString config.nixflix.torrentClients.qbittorrent.webuiPort}";
        disk_path = "/data/shared";
        high_watermark = 0.85;
        low_watermark = 0.80;

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
        ];

        pools = [
          {
            name = "autobrr";
            categories = [ "autobrr" ];
            capacity_gib = 200;
            grace_days = 7;
          }
          {
            name = "arr";
            categories = [
              "sonarr"
              "radarr"
            ];
            grace_days = 14;
          }
        ];
      };
    in
    {
      me.services.graine = {
        subdomain = "graine";
        root = "/var/www/graine";
      };

      persist.directories = [
        "/var/www/graine"
        "/var/lib/graine"
      ];

      packages = [ graine ];

      systemd.tmpfiles.rules = [
        "d /var/www/graine 0755 root root - -"
      ];

      systemd.services.graine = {
        path = [ pkgs.coreutils ];
        script = ''
          export QBIT_PW=$(cat "${config.sops.secrets."qbittorrent/pw".path}")
          exec ${graine}/bin/graine ${graineConfig}
        '';
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "graine";
          WorkingDirectory = "%S/graine";
          LogNamespace = "longterm";
        };
      };

      systemd.timers.graine = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* 00,06,12,18:00:00";
          Persistent = true;
        };
      };
    };
}
