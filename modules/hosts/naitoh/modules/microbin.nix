{
  flake.modules.nixos.naitoh =
    {
      pkgs,
      config,
      ...
    }:
    let
      inherit (config.me.services.microbin) port;
      stateDir = "/var/lib/microbin-container";
      dataDir = "${stateDir}/data";
      btrfs = "${pkgs.btrfs-progs}/bin/btrfs";
    in
    {
      me.services.microbin = {
        subdomain = "share";
        port = 8099;
      };

      users.groups.microbin = { };
      users.users.microbin = {
        isSystemUser = true;
        group = "microbin";
        home = stateDir;
        createHome = false;
        linger = true;
        autoSubUidGidRange = true;
      };

      me.hostSecrets.cloudflared_microbin = { };
      sops.secrets.microbin_pw = { };
      sops.templates."microbin.env" = {
        owner = "microbin";
        content = ''
          MICROBIN_ADMIN_USERNAME=admin
          MICROBIN_ADMIN_PASSWORD=${config.sops.placeholder.microbin_pw}
          MICROBIN_UPLOADER_PASSWORD=${config.sops.placeholder.microbin_pw}
        '';
      };

      services.cloudflared = {
        enable = true;

        tunnels."5fb55271-3fae-4701-a311-522b5417f883" = {
          credentialsFile = config.sops.secrets.cloudflared_microbin.path;

          ingress."share.0xaa.me" = "http://127.0.0.1:${toString config.me.services.microbin.port}";

          default = "http_status:404";
        };
      };

      virtualisation.oci-containers.containers.microbin =
        let
          name = "docker.io/danielszabo99/microbin";
          version = "2.1.4";
        in
        {
          image = name + ":" + version;

          imageFile = pkgs.dockerTools.pullImage {
            imageName = name;
            imageDigest = "sha256:6660e5ccad0d764fa3c0032464ffb8f4b4f28c92a2eb9e39202b94cdc5b68909";
            sha256 = "sha256-osXe26F3zmC2j1AiGjYsyJEbI4VY50H6AXmLQKaeXIo=";

            finalImageTag = version;
          };

          podman.user = "microbin";

          ports = [ "127.0.0.1:${toString port}:8080" ];
          volumes = [ "${dataDir}:/app/microbin_data:U" ];
          environmentFiles = [ config.sops.templates."microbin.env".path ];

          environment = {
            MICROBIN_BIND = "0.0.0.0";
            MICROBIN_PORT = "8080";
            MICROBIN_PUBLIC_PATH = "https://share.0xaa.me";

            MICROBIN_HIDE_HEADER = "true";
            MICROBIN_NO_LISTING = "true";
            MICROBIN_READONLY = "true";
            MICROBIN_EDITABLE = "false";

            MICROBIN_PRIVATE = "false";
            MICROBIN_ENABLE_READONLY = "false";

            MICROBIN_ETERNAL_PASTA = "true";
            MICROBIN_DEFAULT_EXPIRY = "never";
            MICROBIN_MAX_EXPIRY = "never";
            MICROBIN_GC_DAYS = "0";

            MICROBIN_ENABLE_BURN_AFTER = "true";
            MICROBIN_DEFAULT_BURN_AFTER = "0";

            MICROBIN_MAX_FILE_SIZE_UNENCRYPTED_MB = "100";
            MICROBIN_DISABLE_TELEMETRY = "true";
            MICROBIN_DISABLE_UPDATE_CHECKING = "true";

            MICROBIN_ENCRYPTION_CLIENT_SIDE = "false";
            MICROBIN_ENCRYPTION_SERVER_SIDE = "false";
          };

          extraOptions = [
            "--network=microbin-internal"
            "--read-only"
            "--cap-drop=ALL"
            "--security-opt=no-new-privileges"
            "--pids-limit=128"
            "--tmpfs=/tmp:rw,nosuid,nodev,size=128m"
          ];
        };

      # Hard 5 GiB limit, including rootless Podman storage.
      systemd.services.microbin-quota = {
        description = "MicroBin Btrfs quota";
        unitConfig.RequiresMountsFor = "/var/lib";

        serviceConfig.Type = "oneshot";

        script = ''
          set -euo pipefail

          if [ ! -e "${stateDir}" ]; then
            ${btrfs} subvolume create "${stateDir}"
          fi

          ${btrfs} subvolume show "${stateDir}" >/dev/null

          chown microbin:microbin "${stateDir}"
          chmod 0700 "${stateDir}"

          if ! ${btrfs} quota status --is-enabled "${stateDir}"; then
            ${btrfs} quota enable --simple "${stateDir}"
          fi

          ${btrfs} qgroup limit 5G "${stateDir}"

          install -d -m 0700 -o microbin -g microbin "${dataDir}"
        '';
      };

      systemd.services.podman-microbin = {
        requires = [ "microbin-quota.service" ];
        after = [ "microbin-quota.service" ];

        preStart = ''
          ${pkgs.podman}/bin/podman network exists microbin-internal ||
            ${pkgs.podman}/bin/podman network create \
              --internal --disable-dns microbin-internal
        '';
      };
    };
}
