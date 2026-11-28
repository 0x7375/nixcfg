{
  flake.modules.nixos.naitoh =
    { config, pkgs, ... }:
    {
      services.watchdogd.enable = true;
      boot.kernelParams = [
        "panic=10"
        "iTCO_wdt.nowayout=1"
      ];

      systemd.services.crash-notifier = {
        description = "Notify if previous boot ended in a crash";
        wantedBy = [ "multi-user.target" ];
        after = [
          "network-online.target"
          "ntfy-sh.service"
        ];

        wants = [
          "network-online.target"
          "ntfy-sh.service"
        ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          StateDirectory = "crash-notifier";

          LoadCredential = [
            "ntfy_token:${config.sops.secrets."ntfy/token".path}"
          ];
        };

        path = with pkgs; [ curl ];

        script =
          # bash
          ''
            MARKER="/var/lib/crash-notifier/clean_exit"

            if [ ! -f "$MARKER" ]; then
              for i in {1..10}; do
                if curl --fail --connect-timeout 5 \
                  --header @- \
                  -d "Server crashed, rebooted" \
                  http://127.0.0.1:${toString config.me.services.ntfy.port}/status \
                  <<< "Authorization: Bearer $(< "$CREDENTIALS_DIRECTORY/ntfy_token")"; then
                  break
                fi
                echo "Notification failed. Retrying in 5s..."
                sleep 5
              done
            fi

            rm -f "$MARKER"
          '';

        preStop = ''
          touch /var/lib/crash-notifier/clean_exit
        '';
      };
    };
}
