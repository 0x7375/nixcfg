{
  flake.modules.generic.desktop =
    {
      config,
      pkgs,
      ...
    }:
    let
      inherit (config.me) home user;
      calendars = "${home}/.local/share/calendars";
    in
    {
      packages = with pkgs; [
        khal
        vdirsyncer
      ];

      hj.xdg.config.files."khal/config".text =
        # ini
        ''
          [calendars]
          [[default]]
          path = ${calendars}/default/*
          type = discover

          [[unicaen]]
          path = ${calendars}/unicaen/*
          type = discover

          [locale]
          local_timezone = Europe/Paris
          default_timezone = Europe/Paris
          timeformat = %H:%M
          dateformat = %d/%m/%Y
        '';

      services.vdirsyncer = {
        enable = true;

        jobs.calendars = {
          inherit user;
          group = "users";

          forceDiscover = true;

          timerConfig = {
            OnBootSec = "1m";
            OnUnitInactiveSec = "1m";
          };

          config = {
            pairs = {
              default = {
                a = "default_local";
                b = "default_remote";
                collections = [ "from b" ];
              };

              unicaen = {
                a = "unicaen_local";
                b = "unicaen_remote";
                collections = [ "from b" ];
              };
            };

            storages = {
              default_local = {
                type = "filesystem";
                path = "${calendars}/default/";
                fileext = ".ics";
              };

              default_remote = {
                type = "caldav";
                url = "https://calendar.0xaa.me";
                username = "admin";
                "password.fetch" = [
                  "command"
                  "${pkgs.coreutils}/bin/cat"
                  config.sops.secrets.calendar_default_pw.path
                ];
              };

              unicaen_local = {
                type = "filesystem";
                path = "${calendars}/unicaen/";
                fileext = ".ics";
              };

              unicaen_remote = {
                type = "caldav";
                url = "https://webmail.unicaen.fr/dav/22205529@etu.unicaen.fr/";
                username = "22205529@etu.unicaen.fr";
                "password.fetch" = [
                  "command"
                  "${pkgs.coreutils}/bin/cat"
                  config.sops.secrets.uni_pw.path
                ];
              };
            };
          };
        };
      };

      # The NixOS module uses ProtectSystem=strict.
      systemd.services."vdirsyncer@calendars".serviceConfig.ReadWritePaths = [
        calendars
      ];

      systemd.tmpfiles.rules = [
        "d ${calendars} 0700 ${user} users -"
        "d ${calendars}/default 0700 ${user} users -"
        "d ${calendars}/unicaen 0700 ${user} users -"
      ];
    };
}
