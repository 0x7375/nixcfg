{
  flake.modules.nixos.desktop =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    # gtk theme and icon theme need to be symlinked to work, I symlink and swap inside swap-theme
    let
      inherit (config.me.desktop)
        theme
        cursorTheme
        iconTheme
        font
        ;

      fontNameAndSize = font.family + " 11";

      cssContent =
        {
          colorScheme,
          version,
        }:
        # css
        ''
          @import url("file://${theme.package}/share/themes/${theme.name}${
            if colorScheme == "dark" then "-dark" else ""
          }/gtk-${version}.0/gtk.css");

          /* window.csd {
          *   border-radius: 0;
          }*/ 

          window.solid-csd,
          window.solid-csd.maximized,
          window.solid-csd.fullscreen {
            padding: 0px;
            border: none;
            box-shadow: none;
          }
        '';
    in
    {
      options.me.desktop =
        let
          inherit (lib) types mkOption;

          mkThemeOption =
            {
              name,
              package,
            }:
            {
              name = mkOption {
                type = types.str;
                default = name;
              };

              package = mkOption {
                type = types.package;
                default = package;
              };
            };
        in
        {
          theme = mkThemeOption {
            name = "adw-gtk3";
            package = pkgs.adw-gtk3;
          };

          iconTheme = mkThemeOption {
            name = "Gruvbox-Plus";
            package = pkgs.gruvbox-plus-icons;
          };

          cursorTheme =
            mkThemeOption {
              name = "Bibata-Modern-Ice";
              package = pkgs.bibata-cursors;
            }
            // {
              size = mkOption {
                type = types.int;
                default = 24;
              };
            };
        };

      config = {
        programs.dconf.enable = true;

        vars = {
          GTK_THEME = theme.name;
          GTK2_RC_FILES = "${config.me.home}/.config/gtk-2.0/gtkrc";
          XCURSOR_SIZE = toString config.me.desktop.cursorTheme.size;
          XCURSOR_THEME = toString config.me.desktop.cursorTheme.name;
        };

        persistUser.directories = [
          ".config/dconf"
        ];

        programs.dconf.profiles = {
          user.databases = [
            {
              settings = {
                "org/gtk/settings/file-chooser" = {
                  show-hidden = true;
                  sort-directories-first = true;
                };
                "org/gnome/desktop/interface" = {
                  "font-name" = fontNameAndSize;
                  "gtk-theme" = theme.name;
                  "icon-theme" = iconTheme.name;
                  "cursor-theme" = cursorTheme.name;
                  "cursor-size" = lib.gvariant.mkUint16 cursorTheme.size;
                };
              };
            }
          ];
        };

        hj.xdg.data.files."icons/default/index.theme".text = # toml
          ''
            [Icon Theme]
            Inherits = ${cursorTheme.name}
          '';

        packages = with pkgs; [
          gtk3
          font.package
          iconTheme.package
          cursorTheme.package
          theme.package
        ];

        hj.xdg.config.files = {
          "gtk-2.0/gtkrc".text = ''
            gtk-cursor-theme-name = "${cursorTheme.name}"
            gtk-cursor-theme-size = ${toString cursorTheme.size}
            gtk-font-name = "${fontNameAndSize}"
            gtk-icon-theme-name = "${iconTheme.name}"
            gtk-theme-name = "${theme.name}"
            gtk-enable-primary-paste = false
            gtk-decoration-layout =

          '';
          "gtk-3.0/settings.ini".text = ''
            [Settings]
            gtk-recent-files-enabled=false
            gtk-cursor-theme-name=${cursorTheme.name}
            gtk-cursor-theme-size=${toString cursorTheme.size}
            gtk-font-name=${fontNameAndSize}
            gtk-icon-theme-name=${iconTheme.name}
            gtk-theme-name=${theme.name}
            gtk-enable-primary-paste=false
            gtk-decoration-layout=
          '';
          "gtk-3.0/bookmarks".text = ''
            file://${config.me.home}/.config
            file://${config.me.home}/uni
            file://${config.me.home}/repos
          '';
          "gtk-4.0/settings.ini".source = config.hj.xdg.config.files."gtk-3.0/settings.ini".source;

        };

        tinted.files = {
          ".config/gtk-3.0/gtk.css".text =
            palette:
            cssContent {
              colorScheme = palette._theme;
              version = "3";
            }
            + (import ./_gtk3.nix palette);
          ".config/gtk-4.0/gtk.css".text =
            palette:
            cssContent {
              colorScheme = palette._theme;
              version = "4";
            }
            + (import ./_gtk4.nix palette);
        };
      };
    };
}
