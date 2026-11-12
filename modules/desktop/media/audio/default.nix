{
  flake.modules.nixos.desktop =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    lib.mkMerge [
      {
        persistUser.directories = [
          ".config/pulse"
          ".local/state/wireplumber"
          ".config/Meiro"
        ];

        tinted.files.".config/Meiro/colors.json" =
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

        me.desktop.bindings =
          let
            playerctl = lib.getExe pkgs.playerctl;
          in
          {
            XF86AudioRaiseVolume = "noctalia msg volume-up";
            XF86AudioLowerVolume = "noctalia msg volume-down";
            XF86AudioMute = "noctalia msg volume-mute";
            XF86AudioNext = "${playerctl} next";
            XF86AudioPrev = "${playerctl} previous";
            XF86AudioPlay = "${playerctl} play-pause";
            XF86AudioMicMute = "${playerctl} play-pause";
            Prior = "${playerctl} previous";
            Next = "${playerctl} next";
          };

        packages = with pkgs; [
          playerctl
          pwvucontrol
          pavucontrol

          pamixer
          (callPackage ./_meiro.nix { })
        ];

        services.udev.extraRules = # bash
          let
            removeRule = subsystem: ''
              ACTION=="remove", \
              SUBSYSTEM=="${subsystem}", \
              ENV{WAYLAND_DISPLAY}="wayland-1", \
              RUN+="${lib.getExe' pkgs.su "su"} ${config.me.user} -c '${lib.getExe pkgs.playerctl} pause --all-players'"
            '';
          in
          ''
            ${removeRule "bluetooth"}

            ${removeRule "sound"}
          '';

        systemd.user.services.playerctld = {
          description = "MPRIS media player daemon";

          wantedBy = [ "default.target" ];

          serviceConfig = {
            ExecStart = lib.getExe' pkgs.playerctl "playerctld";
            Type = "dbus";
            BusName = "org.mpris.MediaPlayer2.playerctld";
          };
        };

        security.rtkit.enable = true;
        services.pipewire = {
          enable = true;
          pulse.enable = true;
          extraConfig.pipewire = {
            "99-custom" = {
              "context.properties" = {
                "module.x11.bell" = false;

                # audio latency otherwise i think?
                "default.clock.rate" = 48000;
                "default.clock.quantum" = 1024;
                "default.clock.min-quantum" = 1024;
              };
            };
          };
          wireplumber.extraConfig = {
            "51-disable-suspend" = {
              "monitor.bluez.rules" = [
                {
                  matches = [
                    { "node.name" = "~bluez_output.*"; }
                  ];
                  actions = {
                    update-props = {
                      "session.suspend-timeout-seconds" = 0;
                    };
                  };
                }
              ];
            };
          };
        };
      }
      # easyeffects
      (lib.mkIf false {
        packages = with pkgs; [
          easyeffects
          at-spi2-core
        ];

        hj.xdg.config.files = lib.mapAttrs' (
          k: v:
          # Assuming only one of either input or output block is defined, having both in same file not seem to be supported by the application since it separates it by folder
          let
            folder = builtins.head (builtins.attrNames v);
          in
          lib.nameValuePair "easyeffects/${folder}/${k}.json" {
            source = (pkgs.formats.json { }).generate "${folder}-${k}.json" v;
          }
        ) (builtins.fromJSON (builtins.readFile ./easyeffects.json));

        systemd.user.services.easyeffects = {
          description = "Easyeffects daemon";
          requires = [ "dbus.service" ];
          after = [ "graphical-session.target" ];
          partOf = [
            "graphical-session.target"
            "pipewire.service"
          ];

          wantedBy = [ "graphical-session.target" ];

          serviceConfig = {
            ExecStart = "${lib.getExe pkgs.easyeffects} --gapplication-service --load-preset default";
            ExecStop = "${lib.getExe pkgs.easyeffects} --quit";
            Restart = "on-failure";
            RestartSec = 5;
          };
        };
      })
    ];
}
