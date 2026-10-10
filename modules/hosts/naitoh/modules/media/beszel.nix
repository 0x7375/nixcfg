{
  flake.modules.nixos.naitoh =
    { config, ... }:
    let
      inherit (config.services.beszel.hub) port;
    in
    {
      me.services.beszel = {
        subdomain = "home";
        inherit port;
        path = "system/f6jdrznyx4hxkq4";
        webSockets = true;
      };

      persist.directories = [ "/var/lib/private/beszel-hub" ];

      networking.firewall.allowedTCPPorts = [ port ];

      me.hostSecrets."beszel/key" = { };
      # permanent token needs to be generated from the ui
      me.hostSecrets."beszel/token".owner = "beszel-agent";
      me.hostSecrets."beszel/pw" = { };

      sops.templates.beszel-agent.content = ''
        TOKEN=${config.sops.placeholder."beszel/token"}
      '';

      sops.templates.beszel-hub.content = ''
        USER_EMAIL=admin@example.com
        USER_PASSWORD=${config.sops.placeholder."beszel/pw"}
      '';

      systemd.services.beszel-hub = {
        serviceConfig.LoadCredential = [
          "id_ed25519:${config.sops.secrets."beszel/key".path}"
        ];
        preStart = ''
          install -D -m 600 "$CREDENTIALS_DIRECTORY/id_ed25519" "$STATE_DIRECTORY/beszel_data/id_ed25519"
        '';
      };

      services.beszel = {
        hub = {
          enable = true;
          host = "0.0.0.0";
          environment = {
            KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGrkPu4QJhKyEoiI+aADBILeUDcg0tx1Q46x36+jlS1I";
            HUB_URL = "http://127.0.0.1:${toString port}";
          };
          environmentFile = config.sops.templates.beszel-hub.path;
        };
        agent = {
          enable = true;
          smartmon = {
            enable = true;
            deviceAllow = [
              "/dev/nvme0n1"
              "/dev/nvme1n1"
            ];
          };
          environment = {
            EXTRA_FILESYSTEMS = builtins.concatStringsSep "," [
              "/data/shared"
              "/mnt/nvme__NVMe"
              "/mnt/ssd__SSD"
              "/mnt/hdd__HDD"
            ];
            DOCKER_HOST = "unix:///run/podman/podman.sock";
            KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGrkPu4QJhKyEoiI+aADBILeUDcg0tx1Q46x36+jlS1I";
            HUB_URL = "http://127.0.0.1:${toString port}";
          };
          environmentFile = config.sops.templates.beszel-agent.path;
          openFirewall = true;
        };
      };
    };
}
