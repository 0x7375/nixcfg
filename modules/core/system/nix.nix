{ self, ... }:

{
  flake.lib.withMainProgram =
    name: pkg:
    pkg
    // {
      meta = (pkg.meta or { }) // {
        mainProgram = name;
      };
    };

  flake.modules.generic.core =
    {
      config,
      inputs,
      pkgs,
      lib,
      ...
    }:
    let
      mv = inputs.multiverse.multiverse.${pkgs.stdenv.hostPlatform.system}.fast;
    in
    {
      nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (lib.getName pkg) config.unfree-packages;

      _module.args.mv = inputs.multiverse.multiverse.${pkgs.stdenv.hostPlatform.system}.fast;

      nixpkgs.overlays = [
        (final: prev: {
          my = prev.my or { } // self.packages.${final.stdenv.hostPlatform.system};
        })
      ];

      nixpkgs.flake = {
        setFlakeRegistry = false;
        setNixPath = false;
      };

      packages = [ (mv.version "tack" "1.0.1") ];

      nix =
        let
          flakes = lib.filterAttrs (_: input: lib.isType "flake" input) inputs;
          nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakes;
        in
        {
          extraOptions = ''
            warn-dirty = false
            trusted-users = root ${config.me.user}

            connect-timeout = 10
            stalled-download-timeout = 10
            # still build when a cache fails
            fallback = true
          '';

          inherit nixPath;
          package = pkgs.lix;
          channel.enable = false;
          settings = {
            flake-registry = "";
            experimental-features = [ "nix-command flakes" ];
            use-xdg-base-directories = true;
            substituters = [ "https://nix-community.cachix.org" ];
            trusted-public-keys = [ "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=" ];
            auto-optimise-store = true;
            keep-going = true;
            log-lines = 20;
            nix-path = nixPath;
          };
          registry = {
            mv.flake = inputs.multiverse;
            n.flake = inputs.nixpkgs;
            nixpkgs.flake = inputs.nixpkgs;
            t = {
              from.type = "indirect";
              from.id = "tmpl";
              to.type = "git";
              to.url = "https://codeberg.org/0x7E/templates";
            };
            nixcfg = {
              from.type = "indirect";
              from.id = "nixcfg";
              to = {
                type = "git";
                url = "file://${config.me.flakeDir}";
                submodules = true;
              };
            };
          };
        };
    };

  flake.modules.nixos.core =
    { config, ... }:
    {
      nixpkgs.overlays = [
        (final: prev: {
          # adapted from: https://github.com/NixOS/nix/pull/15297
          lix = prev.lix.overrideAttrs (old: {
            patches = (old.patches or [ ]) ++ [ ./nix_shell_packages_env_var.patch ];
            doCheck = false;
            doInstallCheck = false;
          });

          # nix = final.unstable.nix.override {
          #   nix-cli = final.unstable.nix.nix-cli.overrideAttrs (old: {
          #     patches = (old.patches or [ ]) ++ [ ./nix_shell_packages_env_var.patch ];
          #   });
          # };
        })
      ];

      persistUser.directories = [
        ".config/nixcfg"
        ".cache/nix"
        ".local/share/nix"
        ".local/state/nd"
        ".local/state/nix"
      ];

      programs.nh = {
        enable = true;
        flake = config.me.flakeDir;
        clean = {
          enable = false;
          dates = "daily";
          extraArgs = "--keep 5";
        };
      };
    };

  flake.modules.generic.secrets =
    {
      mv,
      config,
      ...
    }:
    {
      sops.secrets.github_token.owner = config.me.user;
      packages = [ (mv.version "tack" "1.0.1") ];
    };
}
