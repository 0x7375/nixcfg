{ inputs, self, ... }:

{
  flake.modules.nixos.naitoh =
    {
      config,
      pkgs,
      ...
    }:

    let
      graine = inputs.graine.packages.${pkgs.stdenv.hostPlatform.system}.default;
    in
    {
      me.services.autobrr = {
        subdomain = "auto";
        inherit (config.services.autobrr.settings) port;
      };

      me.hostSecrets.autobrr_session.owner = config.services.qbittorrent.user;

      persist.directories = [ "/var/lib/private/autobrr" ];

      services.autobrr = {
        enable = true;
        openFirewall = true;
        package = pkgs.auto.autobrr;
        secretFile = config.sops.secrets.autobrr_session.path;
        settings = {
          host = "0.0.0.0";
          checkForUpdates = false;
        };
      };

      packages = [ graine ];

      systemd.services.graine = {
        script = ''
          export QBIT_PW=$(cat "${config.sops.secrets."qbittorrent/pw".path}")
          exec ${graine}/bin/graine http://localhost:${toString config.nixflix.torrentClients.qbittorrent.webuiPort}
        '';
        serviceConfig = {
          Type = "oneshot";
          StateDirectory = "ratio-filter";
          WorkingDirectory = "%S/ratio-filter";
        };
      };

      systemd.timers.graine = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
        };
      };
    };
}
