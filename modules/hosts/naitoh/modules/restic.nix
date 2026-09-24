{ self, ... }:

{
  flake.modules.nixos.naitoh =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    {
      packages = with pkgs; [
        rclone
        restic
      ];

      me.hostSecrets."restic_pw" = { };

      me.hostSecrets."backblaze/account" = { };
      me.hostSecrets."backblaze/key" = { };
      sops.templates."rclone.ini".content =
        # ini
        ''
          [backblaze]
          type        = b2
          account     = ${config.sops.placeholder."backblaze/account"}
          key         = ${config.sops.placeholder."backblaze/key"}
          hard_delete = true
        '';

      vars.RESTIC_PASSWORD_FILE = config.sops.secrets."restic_pw".path;

      services.restic.backups =
        let
          backupConfig =
            let
              remotes = {
                local = {
                  time = "18:00:00";
                  path = "/data/main/backups/restic/";
                };
                backblaze = {
                  time = "22:00:00";
                  path = "rclone:backblaze:restic9678412/";
                };
              };
            in
            {
              remote,
              day,
              paths,
              name,
              exclude,
            }:
            {
              initialize = true;
              passwordFile = config.sops.secrets."restic_pw".path;
              rcloneConfigFile = config.sops.templates."rclone.ini".path;
              repository = remotes.${remote}.path + name;
              inherit paths;
              inherit exclude;
              pruneOpts = [
                "--keep-weekly 4"
                "--keep-monthly 6"
              ];
              timerConfig = {
                OnCalendar = day + " *-*-* " + remotes.${remote}.time;
                Persistent = true;
              };
              rcloneOptions = {
                "fast-list" = "true"; # single api call to list every directory
                "transfers" = "50";
              };
            };

          createBackups =
            name:
            {
              paths,
              day,
              exclude ? [ ],
            }:
            builtins.listToAttrs (
              map
                (remote: {
                  name = "${remote}-${name}";
                  value = backupConfig {
                    inherit
                      remote
                      day
                      paths
                      name
                      exclude
                      ;
                  };
                })
                [
                  "local"
                  "backblaze"
                ]
            );
        in
        (createBackups "syncthing" {
          paths = [ "/data/main/syncthing" ];
          day = "Sat";
          exclude = [
            ".stfolder"
            ".stversions"
            ".stignore"
          ];
        })
        // (createBackups "media" {
          paths = [ "/data/main/.state" ];
          day = "Sun";
        })
        // (createBackups "git" {
          paths = [ "/data/main/backups/git" ];
          day = "Mon";
        });

      systemd.services = lib.mkMerge (
        map (service: self.lib.notifyOnServiceFailure ("restic-backups-" + service)) (
          builtins.attrNames config.services.restic.backups
        )
      );
    };
}
