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
            ".config/Meiro/colors.json" =
              let
                mkMeiroScheme =
                  mode: p:
                  let
                    surfaceContainers =
                      if mode == "dark" then
                        {
                          surface_container_lowest = p.bg0_hard;
                          surface_container_low = p.bg0;
                          surface_container = p.bg0_soft;
                          surface_container_high = p.bg1;
                          surface_container_highest = p.bg2;
                        }
                      else
                        {
                          surface_container_lowest = p.bg0_soft;
                          surface_container_low = p.bg0;
                          surface_container = p.bg0_hard;
                          surface_container_high = p.bg1;
                          surface_container_highest = p.bg2;
                        };

                    black = config.tinted.colors.dark.bg0_hard;
                    darkInk = config.tinted.colors.dark.bg0;
                  in
                  {
                    primary = p.green;
                    on_primary = p.bg0;
                    primary_container = p.bg_green;
                    on_primary_container = p.fg0;

                    secondary = p.yellow;
                    on_secondary = p.bg0;
                    secondary_container = p.neutral_yellow;
                    on_secondary_container = darkInk;

                    tertiary = p.blue;
                    on_tertiary = p.bg0;
                    tertiary_container = p.blue;
                    on_tertiary_container = p.bg0;

                    error = p.red;
                    on_error = p.bg0;
                    error_container = p.bg_red;
                    on_error_container = p.fg0;

                    surface = p.bg0_hard;
                    on_surface = p.fg0;
                    on_surface_variant = p.fg1;

                    surface_dim = p.bg0_hard;
                    surface_bright = p.bg0_soft;

                    outline = p.bg2;
                    outline_variant = p.bg3;

                    inverse_surface = p.fg0;
                    inverse_on_surface = p.bg0;
                    inverse_primary = p.bg_green;

                    scrim = black;
                    shadow = black;
                  }
                  // surfaceContainers;
              in
              {
                generator = lib.generators.toJSON { };
                themed = {
                  light = mkMeiroScheme "light" config.tinted.colors.light;
                  dark = mkMeiroScheme "dark" config.tinted.colors.dark;
                };
              };
          };
        };
      };
    };
}
