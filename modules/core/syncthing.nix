{ self, ... }:

{
  flake.modules.nixos.syncthing =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      h = lib.mapAttrs (name: _: name) config.me.hosts;
      inherit (h)
        cray
        woz

        cutler
        mach

        geim
        shannon
        lamarr
        yoshino
        ;

      inherit (groups)
        linux
        windows
        macOS
        android
        pc
        ;

      groups = rec {
        linux = [
          cray
          woz
        ];
        windows = [ cutler ];
        macOS = [ mach ];
        pc = linux ++ windows ++ macOS;
        android = [
          shannon
          lamarr
          geim
        ];
      };
    in
    {
      # allow watching more files
      boot.kernel.sysctl."fs.inotify.max_user_watches" = 524288;

      services.syncthing = {
        enable = true;
        package = pkgs.syncthing;
        overrideDevices = true;
        overrideFolders = true;
        guiPasswordFile = config.sops.secrets.syncthing_pw.path;
        key = config.sops.secrets."syncthing/key".path;
        cert = "${pkgs.writeText "cert" ''
          -----BEGIN CERTIFICATE-----
          ${config.me.host.syncthing.cert}
          -----END CERTIFICATE-----
        ''}";
        settings = {
          options = {
            urAccepted = -1;
            relaysEnabled = false;
          };
          gui.user = "admin";
        };
      };

      me.syncthing.folders = {
        ds = {
          path = "games/ds";
          devices = linux ++ windows;
        };
        switch = {
          path = "games/switch";
          devices = linux ++ windows;
        };
        gamecube = {
          path = "games/gamecube";
          devices = linux ++ windows;
        };
        dolphin = {
          path = ".local/share/dolphin-emu/StateSaves";
          serverPath = "dolphin";
          devices = linux ++ windows;
        };
        ryujinx = {
          path = ".config/Ryujinx";
          serverPath = "ryujinx";
          devices = linux ++ windows;
          ignorePatterns = [
            "!/bis/user"
            "!/bis/system/save"
            "**"
          ];
        };
        windows = {
          path = "windows";
          devices = linux ++ windows;
        };
        zsh_history = {
          path = ".local/state/zsh";
          serverPath = "zsh";
          devices = linux ++ macOS;
          ignorePatterns = [
            "machine_id"
            "history"
          ];
        };
        pictures = {
          path = "pictures";
          devices = pc ++ android;
        };
        documents = {
          path = "documents";
          devices = linux ++ android;
        };
        photos = {
          path = "photos";
          devices = pc ++ android;
        };
        perso = {
          path = "perso";
          devices = linux;
        };
        uni = {
          path = "uni";
          devices = linux;
        };
        universite = {
          path = "documents/pdf/universite";
          devices = android;
        };
        courses = {
          path = "courses";
          devices = pc ++ android ++ [ yoshino ];
        };
        notes = {
          path = "notes";
          devices = pc ++ android;
        };
      };
    };

  flake.modules.nixos.syncthingClient =
    { config, ... }:
    let
      inherit (config.me) user server home;
    in
    {
      imports = [
        self.modules.nixos.syncthing
      ];

      persistUser.directories = [ ".config/syncthing" ];
      programs.fuse.userAllowOther = true;

      me.hostSecrets."syncthing/key".owner = user;
      me.syncthing.dataRoot = "${home}/";
      sops.secrets.syncthing_pw.owner = user;

      services.syncthing = {
        inherit user;
        dataDir = home;
        settings.devices.${server}.id = config.me.hosts.${server}.syncthing.id;
      };

      systemd.services.syncthing-init.after = [ "graphical.target" ];
    };

  flake.modules.nixos.naitoh =
    {
      lib,
      config,
      ...
    }:
    let
      inherit (config.me) hostname;
    in
    {
      me.services.syncthing = {
        subdomain = "sync";
        port = 8384;
      };

      me.hostSecrets."syncthing/key".owner = "syncthing";
      sops.secrets.syncthing_pw.owner = "syncthing";

      users.users.syncthing.extraGroups = [ "media" ];

      me.syncthing.dataRoot = "/data/main/syncthing/";

      persist.directories = [ "/var/lib/syncthing" ];

      services.syncthing = {
        enable = lib.mkForce true;
        openDefaultPorts = true;
        settings.devices =
          let
            syncthingHosts = lib.filterAttrs (n: v: v.syncthing.id != null && n != hostname) config.me.hosts;
          in
          lib.mapAttrs (_: v: { inherit (v.syncthing) id; }) syncthingHosts;
      };

      systemd.tmpfiles.settings.syncthing."/data/main/syncthing".d = {
        group = "syncthing";
        mode = "0755";
        user = "syncthing";
      };
    };

  flake.modules.darwin.mach =
    {
      secrets,
      config,
      lib,
      ...
    }:
    let
      inherit (config.me) user home;
    in
    {
      sops.secrets."syncthing/config" = {
        owner = user;
        sopsFile = "${secrets}/mach/config.xml";
        format = "binary";
        key = "";
      };

      me.hostSecrets."syncthing/key" = {
        owner = user;
      };

      system.activationScripts.postActivation.text =
        let
          inherit (config.sops) secrets;
        in
        # bash
        lib.mkAfter ''
          dir="${home}/Library/Application Support/Syncthing"
          mkdir -p "$dir"

          cp -f ${secrets."syncthing/config".path} "$dir/config.xml"
          cp -f ${secrets."syncthing/key".path} "$dir/key.pem"

          cat << 'EOF' > "$dir/cert.pem"
          -----BEGIN CERTIFICATE-----
          ${config.me.host.syncthing.cert}
          -----END CERTIFICATE-----
          EOF

          chown -R ${user}: "$dir"
          chmod 600 "$dir/config.xml" "$dir/key.pem" "$dir/cert.pem"
        '';
    };
}
