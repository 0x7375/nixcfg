{ inputs, ... }:

{
  flake.modules.nixos.wayland =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      inherit (lib) getExe';
      cfg = config.me.desktop;
    in
    {
      options.me.desktop = {
        monitorScript = lib.mkOption {
          type = lib.types.package;
          readOnly = true;
          default =
            pkgs.writeShellScriptBin "monitor-setup"
              # bash
              ''
                case "$1" in
                  ${lib.concatStringsSep "\n  " (
                    lib.mapAttrsToList (name: profile: ''
                      ${name})
                        ln -sf "$HOME/.config/mango/profiles/${name}.conf" "$HOME/.config/mango/monitors.conf"
                        ln -sf "${
                          pkgs.writeText "noctalia-layout-${name}" cfg.noctaliaLayouts.${name}
                        }" "$HOME/.config/noctalia/layout.toml"
                        ;;'') cfg.profiles
                  )}
                esac
                ${lib.getExe' pkgs.mango "mmsg"} dispatch reload_config
              '';
        };

        mangoProfiles = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          readOnly = true;
          default = lib.mapAttrs (
            name: profile:
            lib.concatStrings (
              lib.flatten (
                lib.mapAttrsToList (
                  monitor: output:
                  let
                    inherit (output.position) x y;
                  in
                  [
                    "monitor_rule = name:${monitor},scale:${toString cfg.scaling},x:${toString x},y:${toString y}\n"
                  ]
                  ++ map (tag: ''
                    bind = SUPER,${tag},viewcrossmon,${tag},${monitor}
                    bind = SUPER+SHIFT,${tag},tagcrossmon,${tag},${monitor}
                    bind = SUPER+CTRL,${tag},comboview,${tag},${monitor}
                    tag_rule = id:${tag},monitor_name:${monitor},no_hide:1,layout_name:monocle
                  '') output.tags
                ) profile.monitors
              )
            )
          ) cfg.profiles;
        };
      };

      config = {
        nixpkgs.overlays = [
          (final: prev: {
            mango = inputs.mango.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
              patches = [ ./fix_monocle_cross_monitor_focus.patch ];
            });
          })
        ];

        persistUser.directories = [ ".config/mango" ];

        hj.xdg.config.files."zsh/.zshrc".text =
          lib.mkBefore # bash
            ''
              [[ $(tty) == "/dev/tty1" ]] && {
                export XDG_SESSION_TYPE=wayland
                export XDG_SESSION_DESKTOP=mango
                export XDG_CURRENT_DESKTOP=mango
                exec mango
              }
            '';

        programs.xwayland.enable = true;

        systemd.user.targets.mango-session = {
          description = "Mango compositor session";
          bindsTo = [ "graphical-session.target" ];
          wants = [ "graphical-session-pre.target" ];
          after = [ "graphical-session-pre.target" ];
        };

        packages = with pkgs; [
          wl-clipboard-rs
          mango

          # required for vesktop to open links for example
          xdg-utils
          # xwayland-satellite

          slurp
        ];

        xdg.portal = {
          wlr.enable = true;
          extraPortals = with pkgs; [
            xdg-desktop-portal-gtk
            xdg-desktop-portal-wlr
          ];

          config.common = {
            default = [ "gtk" ];
            "org.freedesktop.impl.portal.ScreenCast" = [ "wlr" ];
            "org.freedesktop.impl.portal.ScreenShot" = [ "wlr" ];
            "org.freedesktop.impl.portal.Inhibit" = [ ];
          };
        };

        hj.files = lib.mapAttrs' (
          name: text: lib.nameValuePair ".config/mango/profiles/${name}.conf" { inherit text; }
        ) cfg.mangoProfiles;

        tinted.files.".config/mango/config.conf" =
          let
            mkMangoBind =
              name: cfg:
              let
                parts = lib.splitString "+" name;
                key = lib.last parts;
                modStr = lib.concatStringsSep "+" (
                  map (
                    m:
                    if m == "Mod" then
                      "SUPER"
                    else if m == "Alt" then
                      "ALT"
                    else
                      lib.toUpper m
                  ) (lib.init parts)
                );
                bindStr = if modStr == "" then "NONE,${key}" else "${modStr},${key}";
              in
              "${bindStr},spawn,${cfg.cmd}";

            assignRules = lib.map (cfg: "tags:${cfg.workspace},app_id:${cfg.name}") config.me.desktop.assign;

            floatingRules = lib.map (
              cfg:
              "is_floating:${if cfg.enable then "1" else "0"},${
                if cfg.type == "appid" then "app_id" else cfg.type
              }:${cfg.name}"
            ) config.me.desktop.floating;

            mkMangoKeyValue =
              k: v:
              if builtins.isList v then
                lib.concatMapStringsSep "\n" (item: "${k}=${item}") v
              else
                "${k}=${toString v}";
          in
          {
            stripHash = true;
            generator = lib.generators.toKeyValue { mkKeyValue = mkMangoKeyValue; };
            value = p: {
              numlock_on = 1;
              repeat_rate = 30;
              repeat_delay = 200;
              xkb_rules_layout = "us";
              xkb_rules_options = "compose:menu";
              sloppy_focus = 1;
              warp_cursor = 1;
              focus_on_activate = 1;
              trackpad_natural_scrolling = 1;
              trackpad_disable_while_typing = 1;
              drag_tile_to_tile = 1;
              cursor_size = 24;

              circle_layout = "tile,monocle";

              monocle_tab_mode = 0;
              monocle_no_border = 1;

              # very buggy electron + nvidia otherwise
              sync_obj_enable = 1;

              exchange_cross_monitor = 1;
              scratchpad_cross_monitor = 1;
              focus_cross_monitor = 1;

              no_border_when_single = 1;
              border_px = 4;
              gap_inner_horizontal = 0;
              gap_inner_vertical = 0;
              gap_outer_horizontal = 0;
              gap_outer_vertical = 0;
              border_radius = 0;
              border_color = "0x${p.bg1}ff";
              focus_color = "0x${p.fg2}ff";
              global_color = "0x${p.fg3}ff";
              urgent_color = "0x${p.red}ff";
              scratchpad_color = "0x${p.blue}ff";
              root_color = "0x${p.bg0}ff";
              overlay_color = "0x${p.bg1}ff";

              blur = 0;
              shadows = 0;
              animations = 0;
              enable_hotarea = 0;

              new_is_master = 1;
              default_master_factor = "0.50";
              default_master_count = 1;

              window_rule = [
                "tags:3,app_id:${config.me.desktop.browser}"
                "ignore_maximize:1,app_id:${config.me.desktop.browser}"
                "is_floating:1,title:About"
                "is_floating:1,title:Organizer"
                "is_floating:1,title:Preferences"
                "is_floating:1,app_id:Main|Matplotlib"
                "is_global:1,is_floating:1,title:Picture in picture"
              ]
              ++ assignRules
              ++ floatingRules;

              # env = [ "DISPLAY,:2" ];

              exec = map (_: _.cmd) (lib.filter (c: c.always) (lib.attrValues config.me.desktop.startup)) ++ [
                # "${getExe pkgs.xwayland-satellite} :2"
              ];

              exec_once =
                let
                  env = builtins.concatStringsSep " " [
                    "PATH"
                    "XDG_DATA_DIRS"
                    "WAYLAND_DISPLAY"
                    "XDG_CURRENT_DESKTOP"
                    "XDG_SESSION_DESKTOP"
                    "XDG_SESSION_ID"
                    "LIBVA_DRIVER_NAME"
                    "GBM_BACKEND"
                    "__GLX_VENDOR_LIBRARY_NAME"
                    "TERMINAL"
                  ];
                  importEnvironment = pkgs.writeShellScript "mango-import-environment" ''
                    ${getExe' pkgs.dbus "dbus-update-activation-environment"} --systemd ${env}
                    ${getExe' pkgs.systemd "systemctl"} --user import-environment ${env}
                    ${getExe' pkgs.systemd "systemctl"} --user start mango-session.target
                  '';
                in
                [ "${importEnvironment}" ]
                ++ map (_: _.cmd) (lib.filter (c: !c.always) (lib.attrValues config.me.desktop.startup));

              bind = [
                "SUPER+SHIFT,r,reload_config"
                "SUPER,q,killclient"
                "SUPER,f,togglefullscreen"
                "SUPER,Return,togglefloating"
                "SUPER,g,toggleoverview"
                "SUPER+SHIFT,c,centerwin"

                "SUPER,a,switch_layout"

                "SUPER,TAB,focuslast"

                "SUPER,p,focusstack,prev"
                "SUPER,n,focusstack,next"

                "SUPER,k,focusdir,up"
                "SUPER,j,focusdir,down"
                "SUPER,h,focusdir,left"
                "SUPER,l,focusdir,right"

                "SUPER+CTRL,n,exchange_stack_client,down"
                "SUPER+CTRL,p,exchange_stack_client,up"

                "SUPER+CTRL,k,exchange_client,up"
                "SUPER+CTRL,j,exchange_client,down"
                "SUPER+CTRL,h,exchange_client,left"
                "SUPER+CTRL,l,exchange_client,right"

                "SUPER+SHIFT,h,resizewin,-30,+0"
                "SUPER+SHIFT,j,resizewin,+0,+30"
                "SUPER+SHIFT,k,resizewin,+0,-30"
                "SUPER+SHIFT,l,resizewin,+30,+0"
              ]
              ++ (lib.mapAttrsToList mkMangoBind config.me.desktop.bindings);

              mousebind = [
                "SUPER,btn_left,moveresize,curmove"
                "SUPER,btn_right,moveresize,curresize"
              ];

              source = [ "~/.config/mango/monitors.conf" ];
            };
          };
      };
    };

  flake.modules.nixos.laptop = {
    tinted.files.".config/mango/config.conf".value = {
      trackpad_scroll_factor = 0.3;
      switchbind = [
        "fold,spawn,noctalia msg session lock-and-suspend"
      ];
      gesturebind = [
        "none,up,3,togglefullscreen"
        "none,down,3,togglefullscreen"
        "none,right,3,focuslast"
        "none,left,3,focuslast"
        "none,up,4,toggleoverview"
        "none,down,4,toggleoverview"
      ];
      tap_to_click = 1;
      tap_and_drag = 0;
    };
  };
}
