{
  flake.modules.darwin.mach =
    {
      config,
      pkgs,
      mv,
      lib,
      ...
    }:
    let
      inherit (lib) getExe;
    in
    {
      services.aerospace = {
        package = mv.version "aerospace" "0.21.3-Beta";
        enable = true;
        settings =
          let
            terminal = config.me.desktop.terminal.name;
          in
          {
            config-version = 2;
            after-startup-command = [ ];
            accordion-padding = 50;
            enable-normalization-flatten-containers = true;
            enable-normalization-opposite-orientation-for-nested-containers = true;

            default-root-container-layout = "accordion";
            default-root-container-orientation = "auto";

            on-focused-monitor-changed = [ "move-mouse monitor-lazy-center" ];
            automatically-unhide-macos-hidden-apps = true;

            workspace-to-monitor-force-assignment =
              let
                gen = display: list: lib.genAttrs (map toString list) (_: display);
              in
              (gen "main" (lib.range 1 4)) // (gen "secondary" (lib.range 5 9));

            persistent-workspaces = map toString (lib.range 1 9);

            key-mapping.preset = "qwerty";

            gaps = {
              inner.horizontal = 0;
              inner.vertical = 0;
              outer.left = 0;
              outer.bottom = 0;
              outer.top = 0;
              outer.right = 0;
            };

            mode.main.binding =
              let
                super = "alt-ctrl";
              in
              {
                "${super}-shift-r" = [
                  "reload-config"
                  "mode main"
                ];
                "${super}-enter" = [
                  "layout floating tiling"
                  "mode main"
                ];
                "${super}-a" = "layout tiles accordion horizontal";
                "${super}-q" = "close --quit-if-last-window";
                "${super}-f" = "fullscreen";

                "${super}-t" =
                  "exec-and-forget open -na ${terminal} --args -e ${getExe pkgs.my.tmux-sessionizer} ~/";
                "${super}-e" = "exec-and-forget open -na ${terminal} --args -e ${getExe pkgs.lf}";
                "${super}-shift-e" = "exec-and-forget open -na ${terminal} --args -e sudo ${getExe pkgs.lf}";

                "${super}-shift-t" = "exec-and-forget open -na ${terminal}";
                "${super}-shift-s" = "exec-and-forget ${getExe pkgs.my.swap-theme}";
                "${super}-w" = "exec-and-forget open -a Helium";

                "${super}-h" = "focus left";
                "${super}-j" = "focus down";
                "${super}-k" = "focus up";
                "${super}-l" = "focus right";
                "${super}-p" = "focus left";
                "${super}-n" = "focus right";

                "${super}-shift-h" = "move left";
                "${super}-shift-j" = "move down";
                "${super}-shift-k" = "move up";
                "${super}-shift-l" = "move right";

                "${super}-minus" = "resize smart -50";
                "${super}-equal" = "resize smart +50";

                "${super}-1" = "workspace 1";
                "${super}-2" = "workspace 2";
                "${super}-3" = "workspace 3";
                "${super}-4" = "workspace 4";
                "${super}-5" = "workspace 5";
                "${super}-6" = "workspace 6";
                "${super}-7" = "workspace 7";
                "${super}-8" = "workspace 8";
                "${super}-9" = "workspace 9";

                "${super}-shift-1" = "move-node-to-workspace 1";
                "${super}-shift-2" = "move-node-to-workspace 2";
                "${super}-shift-3" = "move-node-to-workspace 3";
                "${super}-shift-4" = "move-node-to-workspace 4";
                "${super}-shift-5" = "move-node-to-workspace 5";
                "${super}-shift-6" = "move-node-to-workspace 6";
                "${super}-shift-7" = "move-node-to-workspace 7";
                "${super}-shift-8" = "move-node-to-workspace 8";
                "${super}-shift-9" = "move-node-to-workspace 9";

                "${super}-g" = "exec-and-forget open -a \"Mission Control\"";
                "${super}-tab" = "workspace-back-and-forth";
                "${super}-shift-tab" = "move-workspace-to-monitor --wrap-around next";
              };

            on-window-detected = [
              {
                "if".app-id = "app.zen-browser.zen";
                run = "move-node-to-workspace 3";
              }
              {
                "if".app-id = "net.imput.helium";
                run = "move-node-to-workspace 3";
              }
              {
                "if".app-id = "dev.vencord.vesktop";
                run = "move-node-to-workspace 4";
              }
              {
                "if".app-id = "com.github.th-ch.youtube-music";
                run = "move-node-to-workspace 4";
              }
            ];
          };
      };
    };
}
