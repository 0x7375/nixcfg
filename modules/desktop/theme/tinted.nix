{
  flake.modules.nixos.core = {
    persistUser.directories = [
      ".cache/tabler-icons"
      ".local/state/tinted"
    ];
  };

  flake.modules.generic.core =
    {
      lib,
      config,
      ...
    }:
    let
      inherit (config.me) home;
    in
    {
      config = {
        nixpkgs.overlays = [
          (final: prev: {
            my = (prev.my or { }) // {
              swap-theme = import ./_swap-theme.nix {
                inherit config;
                pkgs = final;
              };
            };
          })
        ];

        vars.TINTED_DIR = "${home}/${config.tinted.stateDir}";

        tinted = {
          enable = true;
          inherit (config.me) user;
          homeDir = config.me.home;

          palette = import ./_themes/gruvbox.nix;

          files = {
            "${config.tinted.stateDir}/palette.env" = {
              stripHash = true;
              generator = lib.generators.toKeyValue { };
            };
            "${config.tinted.stateDir}/palette.lua".text = p: ''
              return {
              ${lib.concatStringsSep ",\n" (lib.mapAttrsToList (k: v: "  ${k} = \"${v}\"") p)}
              }
            '';
          };
        };
      };
    };
}
