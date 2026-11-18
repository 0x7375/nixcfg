{
  flake.modules.generic.desktop =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      cfg = config.me.desktop;
    in
    {
      options.me.desktop =
        let
          inherit (lib) mkOption types mkEnableOption;

          mkCmdType =
            extraOpts:
            types.attrsOf (
              types.coercedTo (types.either types.str types.package) (cmd: { cmd = "${cmd}"; }) (
                types.submodule {
                  options = {
                    cmd = mkOption {
                      type = types.coercedTo types.package (p: "${p}") types.str;
                    };
                  }
                  // extraOpts;
                }
              )
            );

          mkRuleType =
            extraOpts:
            types.listOf (
              types.submodule {
                options = {
                  type = mkOption {
                    type = types.enum [
                      "appid"
                      "title"
                    ];
                    default = "appid";
                  };
                  name = mkOption { type = types.str; };
                }
                // extraOpts;
              }
            );
        in
        {
          bindings = mkOption {
            type = mkCmdType {
              release = mkEnableOption "create a release binding";
            };
            default = { };
          };

          startup = mkOption {
            type = mkCmdType {
              always = mkEnableOption "run on window-manager restart";
            };
            default = { };
          };

          floating = mkOption {
            type = mkRuleType {
              enable = mkOption {
                type = types.bool;
                default = true;
              };
            };
            default = [ ];
          };

          assign = mkOption {
            type = mkRuleType {
              workspace = mkOption { type = types.str; };
            };
            default = [ ];
          };

          scaling = mkOption {
            type = lib.types.float;
            default = 1.0;
            description = "Scaling factor";
          };

          open = mkOption {
            type = lib.types.str;
            default = if pkgs.stdenv.isDarwin then "open" else lib.getExe' pkgs.xdg-utils "xdg-open";
          };

          copy =
            let
              inherit (lib) getExe';
            in
            mkOption {
              type = lib.types.str;
              default = if pkgs.stdenv.isDarwin then "pbcopy" else getExe' pkgs.wl-clipboard "wl-copy";
            };

          terminal = {
            name = mkOption {
              type = types.str;
              description = "Default terminal emulator";
            };
            cmd = mkOption {
              type = types.str;
              description = "Default terminal command";
            };
            executable =
              let
                termCfg = cfg.terminal;
              in
              mkOption {
                type = types.str;
                readOnly = true;
                default = pkgs.${termCfg.name} + "/bin/" + termCfg.cmd;
              };
          };

          barFontSize = mkOption {
            type = types.int;
            default = 13;
            description = "Top bar font size";
            internal = true;
          };
        };

      config.vars.TERMINAL = "${cfg.terminal.cmd} -e";
    };

  flake.modules.nixos.desktop =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      inherit (lib) getExe;
      cfg = config.me.desktop;
    in
    {
      hardware.graphics.enable = true;

      hardware.i2c.enable = true;

      users.users.${config.me.user}.extraGroups = [
        "i2c"
        "video"
      ];

      zramSwap.memoryPercent = lib.mkForce 100;

      xdg.terminal-exec.enable = true;
      hj.xdg.config.files."xdg-terminals.list".text =
        builtins.head config.xdg.terminal-exec.settings.default;

      me.desktop.bindings =
        let
          term = cfg.terminal.executable;

          btToggle =
            let
              inherit (lib) getExe';
              airpods = "D4:68:AA:88:8E:32";
            in
            pkgs.writeShellScript "bluetooth-toggle"
              # bash
              ''
                if ${getExe' pkgs.bluez "bluetoothctl"} info ${airpods} | grep -q "Connected: yes"; then
                  echo -e "disconnect ${airpods}\nquit" | ${getExe' pkgs.bluez "bluetoothctl"}
                else
                  echo -e "connect ${airpods}\nquit" | ${getExe' pkgs.bluez "bluetoothctl"}
                fi
              '';

          wizToggle =
            pkgs.writers.writePython3Bin "wiz-toggle" { libraries = [ pkgs.python3Packages.pywizlight ]; }
              # python
              ''
                import asyncio
                from pywizlight import wizlight, PilotBuilder


                async def main():
                    bulb = wizlight("192.168.1.110")
                    try:
                        state = await bulb.updateState()
                        if state.get_scene_id() == 14:
                            await bulb.turn_on(PilotBuilder(colortemp=3000, brightness=255))
                        else:
                            await bulb.turn_on(PilotBuilder(scene=14))
                    finally:
                        await bulb.async_close()

                asyncio.run(main())
              '';

          screenshot = import ./_screenshot.nix { inherit pkgs config; };
          screenrecord = import ./_screenrecord.nix { inherit pkgs config; };
        in
        {
          XF86MonBrightnessUp = "noctalia msg brightness-up all";
          XF86MonBrightnessDown = "noctalia msg brightness-down all";
          Print = "${getExe screenshot} area";
          "Shift+Print" = "${getExe screenshot} monitor";
          "Mod+Print" = "${getExe screenrecord} area";
          "Mod+Shift+Print" = "${getExe screenrecord} monitor";

          "Mod+t" = "${term} -e ${getExe pkgs.my.tmux-sessionizer} ${config.me.home}";
          "Mod+Shift+t" = term;

          "Mod+s" = getExe pkgs.my.tmux-sshr;
          "Mod+Shift+s" = "noctalia msg theme-mode-toggle";
          "Mod+y" = "noctalia msg panel-toggle control-center system";
          "Mod+Shift+y" = "noctalia msg panel-toggle omerfuyar/process-manager:panel";
          "Mod+Alt+b" = btToggle;
          "Mod+Shift+i" = getExe wizToggle;

          "Mod+Shift+e" = getExe (
            pkgs.writeShellApplication {
              name = "color-picker";
              runtimeInputs = with pkgs; [
                coreutils-full
                libnotify
                imagemagick
                hyprpicker
              ];
              text = ''
                size="80x80"
                file=$(mktemp --suffix=.png)
                color=$(hyprpicker -ra | tail -n1) && {
                  convert -size "$size" xc:"$color" "$file" && \
                  notify-send -i "$file" "Color picker" "Copied $color to clipboard"
                }
              '';
            }
          );
        };

      services.dbus.enable = true;
    };
}
