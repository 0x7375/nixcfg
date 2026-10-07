{
  flake.modules.nixos.syncthing =
    { config, lib, ... }:
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
      me.syncthing.folders =
        let
          inherit (groups)
            linux
            windows
            macOS
            android
            pc
            ;
        in
        {
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
}
