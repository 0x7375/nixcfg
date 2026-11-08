{ self, ... }:

{
  flake.lib.mkLaunchdAgent =
    {
      name,
      command,
      background ? true,
      extraConfig ? { },
    }:
    {
      inherit command;
      serviceConfig = {
        Label = name;
        KeepAlive = background;
        RunAtLoad = true;
        ProcessType = if background then "Background" else null;
        StandardOutPath = "/tmp/${name}.out";
        StandardErrorPath = "/tmp/${name}.out";
      }
      // extraConfig;
    };

  flake.modules.darwin.mach =
    {
      inputs,
      config,
      lib,
      pkgs,
      ...
    }:
    {
      me = rec {
        desktop.terminal.font.size = 22;
        home = "/Users/ayko";
        hostname = "mach";
        flakeDir = home + "/.config/nixcfg";
      };

      activation = # bash
        ''
          # disable macos quarantine
          spctl --master-disable > /dev/null 2>&1 || true

          flag_file=/var/db/profile_activated
          [[ ! -e $flag_file ]] && sudo -u ${config.me.user} open ${./modules/profile.mobileconfig} && touch $flag_file
        '';

      # "known to corrupt the Nix Store"
      nix.settings.auto-optimise-store = lib.mkForce false;

      nix-homebrew = {
        enable = true;
        enableRosetta = true;
        inherit (config.me) user;
      };

      homebrew = {
        enable = true;
        brews = [
          "xcode-build-server"
          "xcbeautify"
        ];
        casks = [
          "altserver"
          "sf-symbols"
          "secretive"
          "unnaturalscrollwheels"
          "karabiner-elements"
          "middleclick"
          "signal"
          "font-0xproto-nerd-font"
          "raycast"
        ];
        onActivation.cleanup = "zap";
      };

      packages = with pkgs; [
        wireguard-tools
      ];

      hj.xdg.config.files."karabiner/karabiner.json".source = "${
        inputs.karabiner-ts.packages.${pkgs.stdenv.hostPlatform.system}.default
      }/karabiner.json";

      security.pam.services.sudo_local.touchIdAuth = true;

      environment.etc."pam.d/sudo_local".text = ''
        auth       optional       ${pkgs.pam-reattach}/lib/pam/pam_reattach.so ignore_ssh
        auth       sufficient     pam_tid.so
      '';

      users.users.${config.me.user}.home = config.me.home;

      networking.applicationFirewall = {
        enable = true;
        allowSigned = true;
        allowSignedApp = true;
        enableStealthMode = true;
      };

      # TODO: fix tmux-sshr not using FZF_DEFAULT_OPTS
      environment.etc.zshenv.text = lib.mkAfter ''
        if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
          . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
        fi

        if [ -z "''${__NIX_DARWIN_SET_ENVIRONMENT_DONE-}" ]; then
          . ${config.system.build.setEnvironment}
        fi

        export PATH=/run/current-system/sw/bin:/usr/bin:/bin:$PATH
      '';

      hj.xdg.config.files."zsh/.zshenv".text = config.environment.etc.zshenv.text;

      hj.xdg.config.files."zsh/.zshrc".text = lib.mkBefore ''
        ${config.environment.shellInit}
        ${builtins.concatStringsSep "\n" (
          lib.mapAttrsToList (n: v: "alias ${n}='${v}'") config.environment.shellAliases
        )}
      '';

      launchd.user.agents.theme-switcher = self.lib.mkLaunchdAgent {
        name = "theme-switcher";
        command = "${lib.getExe pkgs.dark-mode-notify} ${lib.getExe pkgs.my.swap-theme} sync";
      };

      launchd.user.agents.syncthing = self.lib.mkLaunchdAgent {
        name = "syncthing";
        command = "${lib.getExe pkgs.syncthing} --no-browser --no-restart";
        background = true;
      };

      hj.files.".hushlogin".text = "";

      networking.computerName = config.networking.hostName;
      vars.LANG = "en_US.UTF-8";
      nixpkgs.hostPlatform = "aarch64-darwin";
      system.stateVersion = 6;
    };
}
