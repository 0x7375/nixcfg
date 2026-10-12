{
  flake.modules.nixos.core =
    { pkgs, lib, ... }:
    {
      aliases.open = "${lib.getExe' pkgs.xdg-utils "xdg-open"}";
    };

  flake.modules.generic.core =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      inherit (lib) getExe getExe';
      git = "${getExe' pkgs.git "git"}";
      cargo = "${getExe pkgs.cargo}";
    in
    {
      aliases = {
        np = "nix profile";
        ns = "nix shell";
        nb = "nix build";
        nr = "nix run";
        nl = "nix repl";

        sw = "nd switch";

        extract = "${getExe' pkgs.atool "aunpack"}";
        compress = "${getExe' pkgs.atool "apack"}";

        mkdir = "mkdir -vp";
        rm = "rm -v";
        cp = "cp -v";
        mv = "mv -v";

        # makes sudo work with aliases
        sudo = "sudo ";
        su = "su -";

        free = "${getExe' pkgs.procps "free"} -h";
        df = "${getExe' pkgs.coreutils "df"} -h";
        du = "${getExe' pkgs.coreutils "du"} -h";

        ffmpeg = "${getExe' pkgs.ffmpeg-full "ffmpeg"} -hide_banner";

        qalc = "${getExe pkgs.libqalculate} -s autocalc";

        grep = "${getExe' pkgs.gnugrep "grep"} --color=always";
        ls = "${getExe' pkgs.coreutils "ls"} --color --group-directories-first -h";
        ll = "${getExe' pkgs.coreutils "ls"} -lha --color --group-directories-first";
        lsblk = "${getExe' pkgs.util-linux "lsblk"} -o NAME,FSTYPE,SIZE,MOUNTPOINT";
        tree = "${getExe pkgs.tree} -L 4";
        dif = "${getExe' pkgs.diffutils "diff"} --color";
        bc = "${getExe pkgs.bc} -l";

        so = "exec $SHELL";

        py = "python";

        temp = "temp=\"mktemp -d\"; cd $temp";
        ".." = "cd ..";
        "..." = "cd ../..";
        "...." = "cd ../../..";

        sys = "systemctl";
        jrl = "journalctl";

        doc = "${cargo} doc --no-deps";
        log = "${git} log --ext-diff";
        show = "${git} show --ext-diff";
      }
      // (lib.genAttrs [
        "diff"
        "status"
        "add"
        "commit"
        "push"
        "pull"
        "clone"
        "branch"
        "remote"
        "revert"
        "restore"
        "stash"
        "switch"
        "worktree"
        "checkout"
        "fetch"
        "rebase"
        "cherry-pick"
        "reflog"
        "resign"
      ] (name: "${git} ${name}"))

      // (lib.genAttrs [
        "run"
        "check"
        "clippy"
      ] (name: "${cargo} ${name}"));

      environment.interactiveShellInit =
        let
          cdDotfiles =
            string:
            # bash
            ''
              pushd ${config.me.flakeDir} >/dev/null
              ${string}
              popd >/dev/null
            '';
        in
        # bash
        ''
          # setup a socket that will be used to open files remotely from tmux
          v() {
            if [ -n "$TMUX" ]; then
              local session=$(tmux display-message -p '#S' 2>/dev/null)
              [ -n "$session" ] && command nvim --listen "/tmp/nvim-$session.sock" "$@" 2> /dev/null || command nvim "$@"
              return
            fi

            command nvim "$@"
          }

          fixpdf() {
              ${getExe' pkgs.poppler-utils "pdftocairo"} -pdf "$1" "''${1%.pdf}-fixed.pdf"
          }

          dotr() {
            ${cdDotfiles
              # bash
              ''
                echo -n "Discard changes? [y/N]"
                read -s -r -k 1 answer

                [[ $answer == "y" ]] && {
                  ${git} restore .
                }
              ''
            }
          }

          dota() {
            ${cdDotfiles
              # bash
              ''
                ${git} add .;
                changes=$(${git} diff --cached --name-status | awk '{
                  if ($1 ~ /^R[0-9]*/) {
                    # For renames, print both old and new filenames
                    print "Rename " $2 " -> " $3
                  } else {
                    print $1 " " $2
                  }
                }' | sed 's/^A /Add /; s/^M /Update /; s/^D /Delete /');

                if [[ -z "$changes" ]]; then
                  echo -e "  No changes to commit"
                else
                  ${git} commit -m "$(printf "%s\n" "$changes")";
                fi

                ${git} pull --rebase;

                echo -en "  Push changes? [y/N]"
                read -s -r -k 1 answer

                [[ $answer == "y" ]] && {
                  ${git} push
                }
              ''
            }
          }

          dotu() {
            ${cdDotfiles ''
              if ! ${git} pull --rebase --autostash; then
                if ${git} diff --name-only --diff-filter=U | grep -q "flake.lock"; then
                  local_time=$(${git} log -1 --format=%ct HEAD -- flake.lock 2>/dev/null || echo 0)
                  remote_time=$(${git} log -1 --format=%ct REBASE_HEAD -- flake.lock 2>/dev/null || echo 0)
                  
                  if [[ $remote_time -gt $local_time ]]; then
                    ${git} checkout REBASE_HEAD -- flake.lock
                  else
                    ${git} checkout HEAD -- flake.lock
                  fi
                  
                  ${git} add flake.lock
                  ${git} rebase --continue
                fi
              fi
            ''}
          }

          dotf() {
            ${cdDotfiles
              # bash
              ''
                ${git} add -N .
                {
                  ${git} diff --color=always
                  ${git} diff --cached --color=always
                } | less -R
              ''
            }
          }

          bump-nvim() {
            ${
              # bash
              cdDotfiles ''
                ${git} add nvim
                ${git} commit -m "chore: update nvim" -- nvim
              ''
            }
          }

          vpn() {
            if [[ $# -eq 0 ]]; then
              echo "Usage: vpn <start|stop|restart|show|list> [interface(s)]"
              return 1
            fi

            action="$1"
            shift

            local is_darwin=0
            [[ $(uname) == "Darwin" ]] && is_darwin=1

            case "$action" in
              start|stop|restart)
                if [[ $# -eq 0 ]]; then
                  echo "No interfaces specified. Please provide at least one interface."
                  return 1
                fi
                for iface in "$@"; do
                  if (( is_darwin )); then
                    [[ "$action" =~ (stop|restart) ]] && sudo wg-quick down "$iface"
                    [[ "$action" =~ (start|restart) ]] && sudo wg-quick up "$iface"
                  else
                    sudo systemctl "$action" "wg-quick-$iface"
                  fi
                done
                ;;
              show)
                  sudo wg show "$@"
                ;;
              list)
                echo -n "Available WireGuard interfaces: "
                if (( is_darwin )); then
                  find /etc/wireguard -name "*.conf" 2>/dev/null | sed 's|.*/||; s|\.conf$||'
                else
                  systemctl list-unit-files 'wg-quick-*.service' | grep -v "static\|alias" | grep "wg-quick-" | awk '{print $1}' | sed 's/wg-quick-\(.*\).service/\1/' | tr '\n' ' ' | sed 's/ $/\n/'
                fi
                ;;
              *)
                echo "Invalid action. Use 'start', 'stop', 'restart', 'list' or 'show'."
                return 1
                ;;
            esac
          }

          r() {
            ${getExe' pkgs.coreutils "realpath"} $(where $1);
          }

          _nix_eval_sanitized() {
              local target="$1"
              local sanitize='x: if builtins.isList x then map (builtins.mapAttrs (k: v: let res = builtins.tryEval v; in if res.success then res.value else "<error>")) x else x'
              local result

              if result=$(nix eval --json --apply "$sanitize" "$target" 2>/dev/null); then
                  printf "%s\n" "$result" | jq -rC
              else
                  nix eval "$target"
              fi
          }

          nhv() {
              local target="path:$FLAKE#nixosConfigurations.''${2:-$HOST}.config.hjem.users.$USER.$1"
              _nix_eval_sanitized "$target"
          }

          nv() {
              local system=''${SYSTEM:-nixos}
              [[ $(uname) == "Darwin" ]] && system=darwin
              local target="path:$FLAKE#''${system}Configurations.''${2:-$HOST}.config.$1"
              _nix_eval_sanitized "$target"
          }
        '';
    };

  flake.modules.nixos.secrets = { config, ... }: {
    environment.shellInit = # bash
      ''
        export GITHUB_TOKEN=$(cat "${config.sops.secrets.github_token.path}")
      '';
  };
}
