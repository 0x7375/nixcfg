{ self, ... }:

{
  flake.modules.nixos.naitoh =
    {
      lib,
      config,
      pkgs,
      ...
    }:

    let
      inputs = [
        "auto-update"
        "helium"
        "zen-browser"
      ];
    in
    {
      me.hostSecrets."codeberg_id".owner = config.me.user;

      systemd.services = lib.mkMerge [
        {
          flake-update = {
            description = "Update flake input and commit if eval succeeds";
            path = with pkgs; [
              nix
              git
              openssh
              unstable.tack
            ];
            script = ''
              set -euo pipefail
              DIR="$HOME/repos/flake"

              export GIT_SSH_COMMAND="ssh -i ${
                config.sops.secrets."codeberg_id".path
              } -o IdentitiesOnly=yes -o StrictHostKeyChecking=no"

              [[ ! -d "$DIR" ]] && git clone --recurse-submodules git@codeberg.org:0x7E/nixcfg "$DIR"
              cd "$DIR"

              git fetch origin
              git reset --hard origin/main

              tack update ${lib.concatStringsSep " " inputs}

              git config user.name "flake-bot"
              git config user.email "actions@noreply"

              if nix flake check --all-systems .?submodules=1; then
                git add .
                if ! git diff --cached --quiet; then
                  last_msg=$(git log -1 --pretty=%s)
                  git -c commit.gpgsign=false commit -m "chore: flake.lock update"
                  git push
                fi
              else
                echo "nix flake check failed, discarding lock update" >&2
              fi
            '';
            serviceConfig = {
              Type = "oneshot";
              User = config.me.user;
            };
          };
        }
        (self.lib.notifyOnServiceFailure "flake-update")
      ];

      systemd.timers.flake-update = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "weekly";
          Persistent = true;
        };
      };
    };
}
