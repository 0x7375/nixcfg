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
                    "monitorrule = name:${monitor},scale:${toString cfg.scaling},x:${toString x},y:${toString y}\n"
                  ]
                  ++ map (tag: ''
                    bind = SUPER,${tag},viewcrossmon,${tag},${monitor}
                    bind = SUPER+SHIFT,${tag},tagcrossmon,${tag},${monitor}
                    bind = SUPER+CTRL,${tag},comboview,${tag},${monitor}
                    tagrule = id:${tag},monitor_name:${monitor},no_hide:1,layout_name:monocle
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
            # pinned to 15.4 until ipc tag client count is fixed
            mango = final.unstable.mango.overrideAttrs (old: rec {
              version = "0.15.4";
              patches = [ ./no_border_in_monocle.patch ];

              src = pkgs.fetchFromGitHub {
                inherit (old.src) owner repo;
                tag = version;
                hash = "sha256-f5l8fsEqaX37sw4tAXpKQ4D3MOfrSQyulAvmUJgkqh8=";
              };
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

            assignRules = lib.map (cfg: "tags:${cfg.workspace},appid:${cfg.name}") config.me.desktop.assign;

            floatingRules = lib.map (
              cfg: "isfloating:${if cfg.enable then "1" else "0"},${cfg.type}:${cfg.name}"
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
              numlockon = 1;
              repeat_rate = 30;
              repeat_delay = 200;
              xkb_rules_layout = "us";
              xkb_rules_options = "compose:menu";
              sloppyfocus = 1;
              warpcursor = 1;
              focus_on_activate = 1;
              trackpad_natural_scrolling = 1;
              disable_while_typing = 1;
              drag_tile_to_tile = 1;
              cursor_size = 24;

              circle_layout = "tile,monocle";

              # very buggy electron + nvidia otherwise
              syncobj_enable = 1;

              exchange_cross_monitor = 1;
              scratchpad_cross_monitor = 1;
              focus_cross_monitor = 1;

              no_border_when_single = 1;
              borderpx = 4;
              gappih = 0;
              gappiv = 0;
              gappoh = 0;
              gappov = 0;
              border_radius = 0;
              bordercolor = "0x${p.bg1}ff";
              focuscolor = "0x${p.fg2}ff";
              globalcolor = "0x${p.fg3}ff";
              urgentcolor = "0x${p.red}ff";
              scratchpadcolor = "0x${p.blue}ff";
              rootcolor = "0x${p.bg0}ff";
              overlaycolor = "0x${p.bg1}ff";

              blur = 0;
              shadows = 0;
              animations = 0;
              enable_hotarea = 0;

              new_is_master = 1;
              default_mfact = "0.50";
              default_nmaster = 1;

              windowrule = [
                "tags:3,appid:${config.me.desktop.browser}"
                "ignore_maximize:1,appid:${config.me.desktop.browser}"
                "isfloating:1,title:About"
                "isfloating:1,title:Organizer"
                "isfloating:1,title:Preferences"
                "isfloating:1,appid:Main|Matplotlib"
                "isglobal:1,isfloating:1,title:Picture in picture"
              ]
              ++ assignRules
              ++ floatingRules;

              # env = [ "DISPLAY,:2" ];

              exec = map (_: _.cmd) (lib.filter (c: c.always) (lib.attrValues config.me.desktop.startup)) ++ [
                # "${getExe pkgs.xwayland-satellite} :2"
              ];

              exec-once =
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
                in
                [
                  "${getExe' pkgs.dbus "dbus-update-activation-environment"} --systemd ${env}"
                  "${getExe' pkgs.systemd "systemctl"} --user import-environment ${env}"
                  "${getExe' pkgs.systemd "systemctl"} --user start mango-session.target"
                ]
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
