{
  flake.modules.generic.core =
    {
      lib,
      pkgs,
      ...
    }:
    let
      toKeyValue = lib.generators.toKeyValue {
        mkKeyValue = lib.generators.mkKeyValueDefault {
          mkValueString =
            v:
            with builtins;
            if isBool v then
              (if v then "True" else "False")
            else if isString v then
              ''"${v}"''
            else
              toString v;
        } " = ";
      };
    in
    {
      packages = [
        (pkgs.btop.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [
            (pkgs.fetchpatch {
              url = "https://github.com/aristocratos/btop/commit/a87dd16e78a862b6a2c4ea0206317d958cdf41de.patch";
              hash = "sha256-SJdj1Mb09wxopenXPVSmdS9fAUOw+3bzB6cnZbQ2nRA=";
            })
          ];
        }))
      ];

      hj.xdg.config.files."btop/btop.conf".text = toKeyValue {
        color_theme = "custom";
        vim_keys = true;
        rounded_corners = false;
        shown_boxes = "proc";
      };

      tinted.files.".config/btop/themes/custom.theme".text = palette: ''
        # All graphs and meters can be gradients
        # For single color graphs leave "mid" and "end" variable empty.
        # Use "start" and "end" variables for two color gradient
        # Use "start", "mid" and "end" for three color gradient

        # Main background, empty for terminal default, need to be empty if you want transparent background
        theme[main_bg]="${palette.bg0}"

        # Main text color
        theme[main_fg]="${palette.fg3}"

        # Title color for boxes
        theme[title]="${palette.fg0}"

        # Higlight color for keyboard shortcuts
        theme[hi_fg]="${palette.yellow}"

        # Background color of selected items
        theme[selected_bg]="${palette.bg0}"

        # Foreground color of selected items
        theme[selected_fg]="${palette.yellow}"

        # Color of inactive/disabled text
        theme[inactive_fg]="${palette.bg0}"

        # Color of text appearing on top of graphs, i.e uptime and current network graph scaling
        theme[graph_text]="${palette.bg2}"

        # Misc colors for processes box including mini cpu graphs, details memory graph and details status text
        theme[proc_misc]="${palette.green}"

        # Cpu box outline color
        theme[cpu_box]="${palette.fg3}"

        # Memory/disks box outline color
        theme[mem_box]="${palette.fg3}"

        # Net up/down box outline color
        theme[net_box]="${palette.fg3}"

        # Processes box outline color
        theme[proc_box]="${palette.fg3}"

        # Box divider line and small boxes line color
        theme[div_line]="${palette.fg3}"

        # Temperature graph colors
        theme[temp_start]="${palette.blue}"
        theme[temp_mid]=""
        theme[temp_end]="${palette.magenta}"

        # CPU graph colors
        theme[cpu_start]="${palette.green}"
        theme[cpu_mid]="${palette.yellow}"
        theme[cpu_end]="${palette.red}"

        # Mem/Disk free meter
        theme[free_start]="${palette.green}"
        theme[free_mid]=""
        theme[free_end]="${palette.green}"

        # Mem/Disk cached meter
        theme[cached_start]="${palette.blue}"
        theme[cached_mid]=""
        theme[cached_end]="${palette.blue}"

        # Mem/Disk available meter
        theme[available_start]="${palette.yellow}"
        theme[available_mid]=""
        theme[available_end]="${palette.yellow}"

        # Mem/Disk used meter
        theme[used_start]="${palette.red}"
        theme[used_mid]=""
        theme[used_end]="${palette.red}"

        # Download graph colors
        theme[download_start]="${palette.blue}"
        theme[download_mid]=""
        theme[download_end]="${palette.blue}"

        # Upload graph colors
        theme[upload_start]="${palette.magenta}"
        theme[upload_mid]=""
        theme[upload_end]="${palette.magenta}"
      '';
    };
}
