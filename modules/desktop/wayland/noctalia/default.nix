{
  flake.modules.nixos.wayland =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      mkTerminal = p: {
        normal = {
          black = p.bg1;
          inherit (p)
            red
            green
            yellow
            blue
            magenta
            cyan
            ;
          white = p.fg3;
        };
        bright = {
          inherit (p) red green yellow;
          black = p.bg3;
          blue = p.fg0;
          magenta = p.bg3;
          cyan = p.bg2;
          white = p.bg0;
        };
        foreground = p.fg0;
        background = p.bg0;
        selectionFg = p.fg1;
        selectionBg = p.bg3;
        cursorText = p.bg0;
        cursor = p.fg1;
      };

      mkScheme = p: {
        mPrimary = p.green;
        mOnPrimary = p.bg0;
        mSecondary = p.yellow;
        mOnSecondary = p.bg0;
        mTertiary = p.blue;
        mOnTertiary = p.bg0;
        mError = p.red;
        mOnError = p.bg0;
        mSurface = p.bg0_hard;
        mOnSurface = p.fg0;
        mSurfaceVariant = p.bg1;
        mOnSurfaceVariant = p.fg1;
        mOutline = p.bg2;
        mShadow = p.bg0;
        mHover = p.blue;
        mOnHover = p.bg0;
        terminal = mkTerminal p;
      };

      inherit (config.tinted.colors) dark light;
      inherit (config.me.services.radicale) url;
    in
    {
      options.me.desktop =
        let
          cfg = config.me.desktop;
          mkNoctaliaLayout =
            {
              main,
              secondary ? null,
            }:
            let
              label = "label";
            in
            # toml
            ''
              [notification]
              monitors = [ "${main}" ]
              ${
                if secondary != null then
                  # toml
                  ''
                    [bar.default.monitor.${secondary}]
                    auto_hide = true
                    reserve_space = false
                  ''
                else
                  ""
              }

              [lockscreen_widgets]
              enabled = true
              schema_version = 2
              widget_order = [  "lockscreen-login-box@${main}", "lockscreen-widget-${label}" ]

                  [lockscreen_widgets.grid]
                  cell_size = 16
                  major_interval = 4
                  visible = true

                  [lockscreen_widgets.widget."lockscreen-login-box@${main}"]
                  box_height = 0.0
                  box_width = 0.0
                  cx = 711.0
                  cy = 765.0
                  output = "${main}"
                  rotation = 0.0
                  type = "login_box"

                  [lockscreen_widgets.widget.lockscreen-widget-${label}]
                  box_height = 128.0
                  box_width = 368.0
                  cx = 711.0
                  cy = 236.0
                  output = "${main}"
                  rotation = 0.0
                  type = "label"

                      [lockscreen_widgets.widget.lockscreen-widget-${label}.settings]
                      background = false
                      background_opacity = 1.0
                      shadow = false
                      title = "Locked"
            '';
        in
        {
          noctaliaLayouts = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            readOnly = true;
            default = lib.mapAttrs (
              name: profile:
              let
                secondaries = builtins.filter (m: m != profile.primary) (builtins.attrNames profile.monitors);
              in
              mkNoctaliaLayout (
                {
                  main = profile.primary;
                }
                // lib.optionalAttrs (secondaries != [ ]) { secondary = builtins.head secondaries; }
              )
            ) cfg.profiles;
          };
        };

      config = {
        persistUser = {
          directories = [
            ".cache/noctalia"
            ".config/noctalia"
            ".local/state/noctalia"
            ".config/Bitwarden CLI"
          ];
        };

        nixpkgs.overlays = [
          (final: prev: {
            # pinned until 5.0.0-beta.9 so my dmenu patch works
            noctalia = final.unstable.noctalia.overrideAttrs (old: rec {
              version = "4dd6f29dbaafde7b11d61ce12685d01441d4a483";
              src = pkgs.fetchFromGitHub {
                inherit (old.src) owner repo;
                rev = version;
                hash = "sha256-Kc3xbv2+z0+aV+t4IL1BfoTtB9MS0zHyI38oiv7zHxc=";
              };

              patches = (old.patches or [ ]) ++ [
                ./patches/truncate_ssid.patch
                ./patches/glyph_dmenu_cli.patch
                ./patches/original_critical_toast.patch
                ./patches/hide_discord_toast_body.patch
              ];
            });

            my =
              let
                expectScript =
                  final.writeScript "fido2-expect"
                    # expect
                    ''
                      #!${lib.getExe final.expect} -f
                      set outfile [lindex $argv 0]
                      set infile  [lindex $argv 1]
                      set ageargs [lrange $argv 2 end]
                      gets stdin pin

                      log_user 0
                      set timeout -1

                      spawn age {*}$ageargs -o $outfile $infile

                      expect {
                          -re {PIN.*: $} { send -- "$pin\r"; exp_continue }
                          -re {.*waiting.*} { exit 1 }
                          timeout { exit 1 }
                          eof
                      }

                      catch {wait} result
                      set code [lindex $result 3]
                      if {$code ne "" && $code != 0} { exit 1 }
                      if {![file exists $outfile]} { exit 1 }
                      exit 0
                    '';

                mkPinLoop = final.writeShellScript "fido2-pin-loop" ''
                  PIN_FILE="/run/user/$(id -u)/noctalia_password"
                  CMD_DESC="$1"; shift
                  RUN="$1"; shift

                  RETRY="0"
                  while true; do
                    rm -f "$PIN_FILE"
                    mkfifo -m 600 "$PIN_FILE"

                    ${final.lib.getExe final.noctalia} msg panel-open me/ask-password:ask-password "$RETRY::$CMD_DESC" >/dev/null 2>&1

                    PIN=$(cat "$PIN_FILE")
                    rm -f "$PIN_FILE"
                    [ -z "$PIN" ] && exit 1

                    if printf "%s\n" "$PIN" | "$RUN" "$@"; then
                      ${final.lib.getExe final.noctalia} msg panel-close me/ask-password:ask-password >/dev/null 2>&1
                      exit 0
                    fi
                    RETRY="1"
                  done
                '';
              in
              (prev.my or { })
              // {
                lock = import ./_scripts/lock.nix final;

                fido2-decrypt = final.writeShellScript "fido2-decrypt" ''
                  if [ "$#" -ne 2 ]; then exit 1; fi
                  IDFILE="$1"
                  SECFILE="$2"
                  OUTFILE=$(mktemp -p "$XDG_RUNTIME_DIR")
                  trap 'shred -u "$OUTFILE" 2>/dev/null || rm -f "$OUTFILE"' EXIT

                  CMD_DESC="age -d -i $(basename "$IDFILE") $(basename "$SECFILE")"

                  ${mkPinLoop} "$CMD_DESC" ${expectScript} "$OUTFILE" "$SECFILE" -d -i "$IDFILE" \
                    && cat "$OUTFILE"
                '';

                fido2-encrypt = final.writeShellScript "fido2-encrypt" ''
                  INFILE=$(mktemp -p "$XDG_RUNTIME_DIR")
                  OUTFILE=$(mktemp -p "$XDG_RUNTIME_DIR")
                  trap 'shred -u "$INFILE" "$OUTFILE" 2>/dev/null || rm -f "$INFILE" "$OUTFILE"' EXIT
                  cat > "$INFILE"

                  CMD_DESC="age -e $*"

                  ${mkPinLoop} "$CMD_DESC" ${expectScript} "$OUTFILE" "$INFILE" -e "$@" \
                    && cat "$OUTFILE"
                '';
              };
          })
        ];

        packages = with pkgs; [
          noctalia
          udisks
          ddcutil
          age-plugin-fido2prf
          bitwarden-cli
          wtype
        ];

        sops.secrets.calendar_pw.owner = config.me.user;

        hj.xdg.data.files = {
          "noctalia/plugins/mango-layout".source = ./plugins/mango_layout;
          "noctalia/plugins/ask-password".source = ./plugins/ask_password;
          "noctalia/plugins/bitwarden".source = ./plugins/bitwarden;
        };

        systemd.user.services.noctalia = {
          wantedBy = [ "mango-session.target" ];
          partOf = [ "mango-session.target" ];
          after = [ "kanshi.service" ];
          wants = [ "kanshi.service" ];
          enableDefaultPath = false;

          serviceConfig = {
            ExecStart = lib.getExe pkgs.noctalia;
            Restart = "always";
            RestartSec = 3;
          };
        };

        hj.xdg.config.files = {
          "noctalia/settings.toml" = {
            generator = (pkgs.formats.toml { }).generate "noctalia-settings";
            value = {
              bar = {
                default = {
                  capsule = false;
                  center = [ "workspaces" ];
                  end = [
                    "tray"
                    "notifications"
                    "clipboard"
                    "brightness"
                    "volume"
                    "battery"
                    "sysmon"
                    "ram"
                    "bluetooth"
                    "network"
                    "clock"
                  ];
                  margin_edge = 0;
                  margin_ends = 0;
                  radius = 0;
                  reserve_space = true;
                  shadow = true;
                  start = [
                    "mango-layout"
                    "active_window"
                    "media"
                  ];
                  widget_spacing = 10;
                };
              };

              battery.warning_threshold = 20;
              brightness = {
                enable_ddcutil = true;
                sync_all_monitors = true;
              };
              calendar = {
                enabled = true;
                account.default = {
                  name = "default";
                  provider = "custom";
                  server_url = url;
                  type = "caldav";
                  username = "admin";
                  credential_source = "file";
                  password_file = config.sops.secrets.calendar_pw.path;
                };
              };

              config = { };

              control_center = {
                sidebar_section = "none";
                shortcuts = [
                  { type = "wifi"; }
                  { type = "bluetooth"; }
                  { type = "caffeine"; }
                  { type = "notification"; }
                  { type = "session"; }
                  { type = "dark_mode"; }
                ];
              };

              desktop_widgets.enabled = false;
              dock.enabled = false;

              lockscreen = {
                allow_empty_password = true;
                blur_intensity = 0.99;
              };

              hooks = {
                session_locked = "systemctl stop --user yubikey-touch-detector";
                session_unlocked = "systemctl start --user yubikey-touch-detector";
                theme_mode_changed = "swap-theme sync";
                started = "swap-theme sync";
              };

              keybinds = {
                cancel = [ "Escape" ];
                down = [
                  "Ctrl+n"
                  "Ctrl+j"
                  "Down"
                ];
                up = [
                  "Ctrl+p"
                  "Ctrl+k"
                  "Up"
                ];
                validate = [
                  "Ctrl+m"
                  "Return"
                ];
              };

              location.auto_locate = true;

              notification = {
                background_opacity = 1.0;
                position = "top_center";
                show_app_name = false;
              };

              osd = {
                position = "top_center";
                kinds.media = false;
              };

              shell = {
                avatar_path = "${config.me.home}/pictures/ghibli/kiki.jpg";
                clipboard_auto_paste = "off";
                clipboard_confirm_clear_history = false;
                polkit_agent = true;
                screen_time_enabled = true;
                settings_show_advanced = true;
                telemetry_enabled = true;
                setup_wizard_enabled = false;

                session.actions = [
                  {
                    action = "lock";
                    enabled = true;
                    variant = "default";
                  }
                  {
                    action = "suspend";
                    enabled = true;
                    variant = "default";
                  }
                  {
                    action = "command";
                    command = "loginctl terminate-user ${config.me.user}";
                    enabled = true;
                    glyph = "logout";
                    label = "Log out";
                    variant = "default";
                  }
                  {
                    action = "shutdown";
                    enabled = true;
                    variant = "destructive";
                  }
                  {
                    action = "reboot";
                    enabled = true;
                    variant = "default";
                  }
                ]
                ++ lib.optionals (config.me.hostname == "cray") [
                  (
                    let
                      switch-to-windows = pkgs.writeShellApplication {
                        name = "switch-to-windows";
                        text = ''
                          ENTRY=$(${lib.getExe pkgs.efibootmgr} | grep -i windows | grep -oP 'Boot\K[0-9A-F]+' | head -1)
                          if [ -n "$ENTRY" ]; then
                            sudo efibootmgr --bootnext "$ENTRY" && systemctl --no-wall reboot
                          fi
                        '';
                      };
                    in
                    {
                      action = "command";
                      command = lib.getExe switch-to-windows;
                      enabled = true;
                      glyph = "brand-windows-filled";
                      label = "Reboot to Windows";
                      variant = "default";
                    }
                  )
                  {
                    action = "command";
                    command = "systemctl --no-wall reboot --firmware-setup";
                    enabled = true;
                    glyph = "settings";
                    label = "Reboot to UEFI";
                    variant = "default";
                  }
                ];
                animation = {
                  enabled = true;
                  speed = 2.0;
                };
                launcher = {
                  categories = false;
                };
                panel = {
                  open_near_click_control_center = true;
                  session_placement = "floating";
                };
                shadow.alpha = 0.04;
              };

              nightlight.enabled = false;

              theme = {
                custom_palette = "nix";
                source = "custom";
                templates = {
                  enable_builtin_templates = false;
                  enable_community_templates = false;
                };
              };

              wallpaper.transition_on_startup = false;

              widget = {
                bluetooth.show_label = true;
                sysmon.show_value = false;
                brightness.show_label = false;
                media.hide_when_no_media = true;
                ram = {
                  show_value = false;
                  stat = "ram_pct";
                };
                tray = {
                  anchor = false;
                  capsule = false;
                  drawer = true;
                };
                volume.show_label = false;
                workspaces = {
                  capsule = false;
                  label_source = "id";
                  empty_color = "outline";
                  focused_color = "on_surface";
                  hide_when_empty = true;
                  style = "minimal";
                  occupied_color = "outline";
                };
                mango-layout.type = "me/mango-layout:mango-layout";
              };

              plugins.enabled = [
                "me/mango-layout"
                "me/ask-password"
                "me/bitwarden"
                "nightwatch75/file-search"
              ];

              plugin_settings = {
                "nightwatch75/file-search" = {
                  show_hidden = true;
                  exclude_dirs = builtins.concatStringsSep "," [
                    ".git"
                    "node_modules"
                    ".cache"
                    ".venv"
                    ".stfolder"
                    ".stversions"
                    ".expo"
                    "doc"
                    "bin"
                    "target"
                    ".Trash-1000"
                  ];
                };

                "me/bitwarden" =
                  let
                    inherit (config.me.host.securityKey) name;
                    inherit (config.me.hosts) backupKey mainKey;
                  in
                  {
                    decrypt_cmd = "${pkgs.my.fido2-decrypt} ${config.me.host.securityKey.prfPath} ${./secrets/bitwarden_pw_${name}.age}";
                    export_encrypt_cmd = "${pkgs.my.fido2-encrypt} -i ${mainKey.securityKey.prfPath} -i ${backupKey.securityKey.prfPath}";
                  };
              };
            };
          };
          "noctalia/palettes/nix.json" = {
            generator = lib.strings.toJSON;
            value = {
              dark = mkScheme dark;
              light = mkScheme light;
            };
          };
          "noctalia/notification-rules.json" = {
            generator = lib.strings.toJSON;
            value.rules = [
              {
                action = "block";
                pattern = "Youtube_Music";
              }
              # {
              #   action = "hide";
              #   pattern = "vesktop";
              # }
            ];
          };
        };

        me.desktop = {
          bindings = {
            "Mod+x" = "noctalia msg notification-clear-active";
            "Mod+i" = "noctalia msg bar-toggle";
            "Mod+d" = "noctalia msg panel-toggle launcher";
            "Mod+c" = "noctalia msg panel-toggle clipboard";
            "Mod+r" = "noctalia msg panel-toggle control-center notifications";
            "Mod+Shift+m" = "noctalia msg panel-toggle control-center weather";
            "Mod+Shift+f" = "noctalia msg panel-toggle launcher \"/fs \"";
            "Mod+Shift+b" = "noctalia msg plugin me/bitwarden:service all toggle_menu";

            "Mod+m" = pkgs.writeShellScript "open-note" ''
              # Try to open an existing note and create a new one otherwise
              note=$(ls -t $HOME/{notes,courses}/*.{org,md,csv} 2>/dev/null \
                | sed -E 's|.*/||; s/\.(org|md|csv)$//' \
                | ${lib.getExe pkgs.noctalia} dmenu -p "Open or create a note..." -g notebook)

              [[ -n "$note" ]] || exit 0

              for dir in notes courses; do
                for ext in org md csv; do
                  file="$HOME/$dir/$note.$ext"
                  [[ ! -f "$file" ]] && continue

                  cd "$HOME/$dir"
                  exec $TERMINAL $EDITOR "$file"
                done
              done

              exec $TERMINAL $EDITOR "$HOME/notes/$note.org"
            '';
            "Mod+b" = lib.getExe (import ./_scripts/open-bookmark.nix pkgs);
            "Mod+Shift+p" = "noctalia msg panel-toggle launcher \"/session \"";
          };
        };
      };
    };

  flake.modules.nixos.laptop =
    { lib, pkgs, ... }:
    {
      hj.xdg.config.files."noctalia/settings.toml".value = {
        idle = {
          pre_action_fade_seconds = 0;
          behavior_order = [
            "screen-off"
            "lock-and-suspend"
          ];
          behavior = {
            screen-off = {
              command = "noctalia msg dpms-off";
              resume_command = "noctalia msg dpms-on";
              timeout = 300;
              enabled = true;
            };
            lock-and-suspend = {
              action = "command";
              command = "${lib.getExe pkgs.my.lock} lock-and-suspend";
              resume_command = "noctalia msg dpms-on";
              timeout = 600;
              enabled = true;
            };
          };
        };
      };
    };
}
