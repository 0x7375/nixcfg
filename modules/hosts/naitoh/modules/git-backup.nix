{
  flake.modules.nixos.naitoh =
    {
      pkgs,
      config,
      ...
    }:
    {
      me.hostSecrets."codeberg_id" = { };

      systemd.services.git-backup = {
        path = with pkgs; [
          git
          coreutils
          curl
          jq
          openssh
        ];
        script =
          # bash
          ''
            remote_url="https://codeberg.org"
            user="0x7E"
            remote="''${remote_url}/''${user}"
            backup_dir="/data/main/backups/git"
            mkdir -p "$backup_dir"

            export GIT_SSH_COMMAND="ssh -i ${
              config.sops.secrets."codeberg_id".path
            } -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes"

            repos=$(curl -s "''${remote_url}/api/v1/users/$user/repos" | jq -r '.[].clone_url')

            private=(
              nix-secrets
              csp-graphes
              web-mvcr
              battle-arena
              todo
              bio-zola
              recipes
              pyplanet
              15-puzzle
              token2-totp-cli
              asahi-firmware
            )

            for repo in "''${private[@]}"; do
                repos+=$'\n'"git@codeberg.org:''${user}/''${repo}.git"
            done

            for repo in $repos; do
              repo_name=$(basename "$repo" .git)
              repo_dir="$backup_dir/$repo_name"
              
              if [[ -d $repo_dir ]]; then
                cd "$repo_dir"
                git fetch --all --prune
              else
                git clone --bare "$repo" "$repo_dir"
              fi
            done
          '';
        serviceConfig.Type = "oneshot";
      };

      systemd.timers.git-backup = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "weekly";
          Persistent = true;
        };
      };
    };
}
