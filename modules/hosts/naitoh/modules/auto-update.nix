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
        "multiverse"
        "helium"
        "zen-browser"
      ];
    in
    {
      me.hostSecrets."codeberg_id".owner = config.me.user;

      systemd.services = lib.mkMerge [
        {
          flake-update = {
            description = "Update flake inputs and commit if system changes and eval succeeds";
            path = with pkgs; [
              nix
              git
              openssh
              tack
            ];
            script = ''
              set -euo pipefail

              DIR="$HOME/repos/flake"
              LOCKFILE=".tack/pins.lock.json"

              export GIT_SSH_COMMAND="ssh -i ${
                config.sops.secrets."codeberg_id".path
              } -o IdentitiesOnly=yes -o StrictHostKeyChecking=no"

              if [[ ! -d "$DIR" ]]; then
                git clone --recurse-submodules git@codeberg.org:0x7E/nixcfg "$DIR"
              fi

              cd "$DIR"

              git fetch origin
              git reset --hard origin/main

              # Evaluate every NixOS configuration's system derivation.
              system_drvs() {
                nix eval --raw --apply '
                  configs:
                    builtins.concatStringsSep "\n" (
                      builtins.map
                        (name:
                          name + "=" +
                          (builtins.getAttr name configs).config.system.build.toplevel.drvPath
                        )
                        (builtins.attrNames configs)
                    )
                ' '.?submodules=1#nixosConfigurations'
              }

              old_drvs=$(system_drvs)

              if ! tack update ${lib.concatStringsSep " " inputs}; then
                echo "Tack update failed, discarding lock update" >&2
                git restore -- "$LOCKFILE"
                exit 1
              fi

              # Skip evaluation and commits if no pins changed.
              if git diff --quiet -- "$LOCKFILE"; then
                echo "No input updates"
                exit 0
              fi

              if ! new_drvs=$(system_drvs); then
                echo "System evaluation failed, discarding lock update" >&2
                git restore -- "$LOCKFILE"
                exit 1
              fi

              # Ignore updates that don't affect any NixOS system.
              if [[ "$old_drvs" == "$new_drvs" ]]; then
                echo "No system derivations changed, discarding lock update"
                git restore -- "$LOCKFILE"
                exit 0
              fi

              if ! nix flake check --all-systems .?submodules=1; then
                echo "nix flake check failed, discarding lock update" >&2
                git restore -- "$LOCKFILE"
                exit 1
              fi

              git config user.name "flake-bot"
              git config user.email "actions@noreply"

              git add -- "$LOCKFILE"

              if ! git diff --cached --quiet; then
                git -c commit.gpgsign=false commit -m "chore(deps): update pins"
                git push
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
          OnCalendar = "daily";
          Persistent = true;
        };
      };
    };
}
