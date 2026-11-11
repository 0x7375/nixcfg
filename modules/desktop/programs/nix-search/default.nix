{
  flake.modules.nixos.desktop = {
    persistUser.directories = [
      ".cache/nix-search-tv"
    ];
  };

  flake.modules.generic.desktop =
    {
      pkgs,
      lib,
      config,
      inputs,
      ...
    }:
    let
      inherit (pkgs.stdenv.hostPlatform) system;
    in
    {
      nixpkgs.overlays = [
        (final: prev: {
          # fork with stable package version in preview aswell
          nix-search-tv = prev.nix-search-tv.overrideAttrs {
            src = pkgs.fetchFromGitHub {
              owner = "0x7375";
              repo = "nix-search-tv";
              rev = "439e6c1a2bf598d892ab1364e96a462d8ed4b554";
              hash = "sha256-1HFhLBX5SMi4HcRLK/zXocZ+lcCpHWEeeczQ8fUYGgA=";
            };
          };
        })
      ];

      packages = [ pkgs.nix-search-tv ];

      hj.xdg.config.files."nix-search-tv/config.json" = {
        generator = lib.generators.toJSON { };
        value = {
          indexes = [
            "nixpkgs"
            "nixos"
            "home-manager"
            "noogle"
            "darwin"
          ];
          experimental = {
            options_file.hjem = inputs.hjem.packages.${system}.docs-json + "/share/doc/hjem/options.json";
            package_versions.stable = "nixos-26.05";
          };
        };
      };

      programs.tmux.extraConfig = # tmux
        ''
          bind-key m new-window ${lib.getExe (pkgs.writeShellScriptBin "nst" (builtins.readFile ./nix-search-fzf.sh))}
        '';

      systemd.timers.clone-repos = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "daily";
          Persistent = true;
        };
      };

      systemd.services.clone-repos = {
        script = ''
          mkdir -p "$HOME/repos"
          SHALLOW=("--depth=1" "--single-branch" "--no-tags")

          while read -r name url; do
            [[ -z "$name" ]] && continue
            target="$HOME/repos/$name"
            [[ -d "$target" ]] && git -C "$target" pull || git clone "$url" "$target" "''${SHALLOW[@]}"
          done <<EOF
          home-manager https://github.com/nix-community/home-manager
          nix-darwin https://github.com/nix-darwin/nix-darwin
          nixpkgs https://github.com/nixos/nixpkgs
          EOF
        '';
        serviceConfig = {
          Type = "oneshot";
          User = config.me.user;
        };
        path = with pkgs; [
          git
          openssh
        ];
      };
    };
}
