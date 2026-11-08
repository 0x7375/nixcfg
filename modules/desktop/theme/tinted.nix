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

        tinted = rec {
          enable = true;
          inherit (config.me) user;
          homeDir = config.me.home;

          palette =
            let
              mkUnique = color: {
                dark = color;
                light = color;
              };
            in
            {
              _theme = {
                dark = "dark";
                light = "light";
              };
              bg0_hard = {
                dark = "#1D2021";
                light = "#F2E5BC";
              };
              bg0 = {
                dark = "#282828";
                light = "#FBF1C7";
              };
              bg0_soft = {
                dark = "#32302F";
                light = "#F9F5D7";
              };
              bg1 = {
                dark = "#3C3836";
                light = "#EBDBB2";
              };
              bg2 = {
                dark = "#504945";
                light = "#D5C4A1";
              };
              bg3 = {
                dark = "#665C54";
                light = "#BDAE93";
              };
              bg4 = {
                dark = "#7C6F64";
                light = "#A89984";
              };
              gray = mkUnique "#928374";

              neutral_red = mkUnique "#CC241D";
              red = {
                dark = "#FB4934";
                light = "#9D0006";
              };
              bg_red = {
                dark = "#722529";
                light = "#fc9487";
              };

              neutral_green = mkUnique "#98971A";
              green = {
                dark = "#b8bb26";
                light = "#79740E";
              };
              bg_green = {
                dark = "#62693e";
                light = "#d5d39b";
              };

              neutral_yellow = mkUnique "#D79921";
              yellow = {
                dark = "#FABD2F";
                light = "#B57614";
              };

              neutral_blue = mkUnique "#458588";
              blue = {
                dark = "#83A598";
                light = "#076678";
              };

              neutral_magenta = mkUnique "#B16286";
              magenta = {
                dark = "#D3869B";
                light = "#8F3F71";
              };

              neutral_cyan = mkUnique "#689D6A";
              cyan = {
                dark = "#8EC07C";
                light = "#427B58";
              };
              bg_cyan = {
                dark = "#49503b";
                light = "#e8e5b5";
              };

              neutral_orange = mkUnique "#D65D0E";
              orange = {
                dark = "#FE8019";
                light = "#AF3A03";
              };
            }
            // (
              let
                swap = c: {
                  dark = c.light;
                  light = c.dark;
                };
                bgs = [
                  "bg4"
                  "bg3"
                  "bg2"
                  "bg1"
                  "bg0_soft"
                  "bg0"
                  "bg0_hard"
                ];
              in
              builtins.listToAttrs (
                map (name: {
                  name = builtins.replaceStrings [ "bg" ] [ "fg" ] name;
                  value = swap palette.${name};
                }) bgs
              )
            );

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
