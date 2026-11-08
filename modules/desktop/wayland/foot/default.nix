{
  flake.modules.nixos.foot =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      mkColors = p: {
        foreground = p.fg0;
        background = p.bg0;
        regular0 = p.bg1;
        regular1 = p.red;
        regular2 = p.green;
        regular3 = p.yellow;
        regular4 = p.blue;
        regular5 = p.magenta;
        regular6 = p.cyan;
        regular7 = p.fg4; # completion text

        bright0 = p.bg2;
        bright1 = p.red;
        bright2 = p.green;
        bright3 = p.yellow;
        bright4 = p.blue;
        bright5 = p.magenta;
        bright6 = p.cyan;
        bright7 = p.fg0;
      };
    in
    {
      me.desktop.terminal = {
        name = "foot";
        cmd = "footclient";
      };

      me.desktop.startup.foot = "${lib.getExe pkgs.foot} --server";

      xdg.terminal-exec.settings.default = [ "footclient.desktop" ];

      nixpkgs.overlays = [
        (final: prev: {
          foot = prev.foot.overrideAttrs (old: {
            patches = (old.patches or [ ]) ++ [
              ./usable_scrolling.patch
            ];
          });
        })
      ];

      programs.foot = {
        enable = true;
        settings =
          let
            inherit (config.tinted.hex) dark light;
          in
          {
            main =
              let
                inherit (config.me.desktop.terminal.font) family size;
              in
              {
                font = "${family}:size=${toString size}";
                horizontal-letter-offset = 0;
                vertical-letter-offset = 0;
                pad = "20x20 center";
                selection-target = "clipboard";
                dpi-aware = "no";
              };

            bell = {
              urgent = "no";
              notify = "no";
            };

            scrollback = {
              lines = 10000;
              multiplier = 18.0;
              indicator-position = "relative";
              indicator-format = "line";
            };

            cursor = {
              style = "block";
              blink = "no";
            };

            mouse = {
              hide-when-typing = "yes";
            };

            mouse-bindings = {
              primary-paste = "none";
            };

            key-bindings = {
              clipboard-paste = "Mod1+v";
              clipboard-copy = "Mod1+c";
              font-decrease = "Mod1+Shift+d";
              font-increase = "Mod1+Shift+u";
              font-reset = "Mod1+Shift+r";
            };

            colors-dark = mkColors dark;
            colors-light = mkColors light;
          };
      };
    };
}
