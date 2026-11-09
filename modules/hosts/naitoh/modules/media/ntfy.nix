{
  flake.lib.notifyOnServiceFailure = service: {
    ${service}.unitConfig.OnFailure = "service-failure-notify@%N.service";
  };

  flake.modules.nixos.naitoh =
    {
      pkgs,
      config,
      ...
    }:
    let
      inherit (config.me) services;
      inherit (services.ntfy) port;
    in
    {
      me.services.ntfy = {
        subdomain = "notify";
        port = 8719;
        webSockets = true;
      };

      persist.directories = [
        {
          directory = "/var/lib/private/ntfy-sh";
          user = "nobody";
          group = "nogroup";
          mode = "0755";
        }
      ];

      services.ntfy-sh = {
        enable = true;
        settings = {
          base-url = "http://localhost:" + toString port;
          listen-http = ":" + toString port;
          auth-default-access = "read-write";
        };
      };
      networking.firewall.allowedTCPPorts = [ port ];

      systemd.services."service-failure-notify@" =
        let
          failureNotifier = pkgs.writeShellApplication {
            name = "service-failure-notify";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.curl
              pkgs.systemd
            ];
            text = ''
              unit="$1"
              url="http://localhost:${toString port}/status"

              notify() {
                curl \
                  --silent \
                  --show-error \
                  --fail \
                  --retry 5 \
                  --retry-connrefused \
                  --retry-delay 2 \
                  -d "Service $unit failed" \
                  "$url" || true
              }

              unresolved() {
                local state
                state="$(systemctl show --property=ActiveState --value "$unit" 2>/dev/null || true)"

                case "$state" in
                  failed|activating|deactivating) return 0 ;;
                  *) return 1 ;;
                esac
              }

              wait_and_check() {
                local remaining="$1"

                while (( remaining > 0 )); do
                  sleep 5
                  remaining=$((remaining - 5))

                  if ! unresolved; then
                    return 1
                  fi
                done

                return 0
              }

              notify

              for delay in 320 600 2700; do
                wait_and_check "$delay" || exit 0
                notify
              done

              while true; do
                wait_and_check 86400 || exit 0
                notify
              done
            '';
          };
        in
        {
          description = "Send notification when a service fails";
          after = [ "ntfy-sh.service" ];
          requires = [ "ntfy-sh.service" ];
          serviceConfig = {
            Type = "exec";
            ExecStart = "${failureNotifier}/bin/service-failure-notify %i";
          };
        };
    };
}
