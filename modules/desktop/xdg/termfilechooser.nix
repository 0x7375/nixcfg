{
  flake.modules.nixos.desktop =
    {
      pkgs,
      mv,
      config,
      lib,
      ...
    }:
    {
      nixpkgs.overlays = [
        (final: prev: {
          xdg-desktop-portal-termfilechooser = mv.version "xdg-desktop-portal-termfilechooser" "1.4.3";

          file-handler = pkgs.stdenv.mkDerivation {
            name = "file-handler";
            src = ./.;
            dontUnpack = true;

            nativeBuildInputs = with pkgs; [
              dbus.dev
              pkg-config
            ];

            buildPhase = ''
              gcc -o file-handler $src/file-handler.c $(pkg-config --cflags --libs dbus-1)
            '';

            installPhase = ''
              mkdir -p $out/bin
              cp file-handler $out/bin
            '';

            meta.mainProgram = "file-handler";
          };
        })
      ];

      xdg.portal = {
        extraPortals = [ pkgs.xdg-desktop-portal-termfilechooser ];
        config.common."org.freedesktop.impl.portal.FileChooser" = "termfilechooser";
      };

      vars = {
        GDK_DEBUG = "portals";
        GTK_USE_PORTAL = "1";
      };

      hj.xdg.config.files."xdg-desktop-portal-termfilechooser/config".text =
        let
          env = pkgs.buildEnv {
            name = "lf-wrapper-env";
            paths = with pkgs; [
              lf
              gnused
              coreutils
              bashInteractive
              zsh
              git
            ];
          };
          inherit (config.me.desktop) terminal;
        in
        # ini
        ''
          [filechooser]
          env=PATH='${env}/bin'
          env=TERMCMD='${lib.getExe pkgs.${terminal.name}} -T filechooser -e'
          cmd='${pkgs.xdg-desktop-portal-termfilechooser}/share/xdg-desktop-portal-termfilechooser/lf-wrapper.sh'
          default_dir=$XDG_DOWNLOAD_DIR
        '';

      me.desktop.floating = [
        {
          type = "title";
          name = "filechooser";
        }
      ];

      vars.QT_QPA_PLATFORMTHEME = "xdgdesktopportal";

      systemd.user.services."file-handler".serviceConfig.ExecStart = "${lib.getExe pkgs.file-handler}";

      xdg.desktopEntries.lf = {
        exec = "${lib.getExe pkgs.lf} %u";
        terminal = true;
        name = "Lf";
        type = "Application";
      };

      hj.xdg.data.files."dbus-1/services/org.freedesktop.FileManager1.service".text = # ini
        ''
          [D-BUS Service]
          Name=org.freedesktop.FileManager1
          Exec=${lib.getExe pkgs.file-handler}
        '';

      packages = [
        (pkgs.writeShellScriptBin "switch-file-chooser" ''
          dir=$HOME/.config/xdg-desktop-portal
          file=$dir/portals.conf
          mkdir -p $dir

          if [[ -f $file ]]; then
            rm -f $file
            echo "Switching to terminal file chooser..."
          else
            printf '[preferred]\ndefault=gtk\norg.freedesktop.impl.portal.FileChooser=gtk\n' > "$file"
            echo "Switching to gtk file chooser..."
          fi
          systemctl restart --user xdg-desktop-portal
        '')
      ];
    };
}
