{
  flake.modules.nixos.syncthing =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.me.syncthing;
      inherit (config.me) hostname;
      isServer = hostname == config.me.server;

      inherit (lib) mkOption types;

      defaultPatterns = [
        # (?d) means syncthing is allowed to delete it if parent is empty otherwise
        "(?d).cache"
        "(?d)bin"
        "(?d)build"
        "(?d).build"
        "(?d)node_modules"
        "(?d).git"
        "(?d).venv"
        "(?d).expo"
        "(?d)*.class"
        "(?d)*.o"
        "(?d)*.toc"
        "(?d)*.aux"
        "!capture.log"
        "(?d)*.log"
        "(?d)*.out"
        "(?d)*.idx"

        # windows
        "(?d)desktop.ini"

        # macos
        "(?d).DS_Store"
        "(?d).localized"
        "(?d)Photos Library.photoslibrary"
      ];

      folderSubmodule =
        { name, config, ... }:
        {
          options = {
            devices = mkOption {
              type = types.listOf types.str;
              default = [ ];
            };
            path = mkOption {
              type = types.str;
              default = name;
            };
            serverPath = mkOption {
              type = types.str;
              default = config.path;
            };
            ignorePatterns = mkOption {
              type = types.listOf types.str;
              default = [ ];
            };
          };
        };

      activeFolders = lib.filterAttrs (_: f: isServer || lib.elem hostname f.devices) cfg.folders;
    in
    {
      options.me.syncthing = {
        dataRoot = mkOption {
          type = types.str;
          default = "~/";
        };
        folders = mkOption {
          type = types.attrsOf (types.submodule folderSubmodule);
          default = { };
        };
      };

      config = {
        services.syncthing.settings.folders = lib.mapAttrs (_: f: {
          path = cfg.dataRoot + (if isServer then f.serverPath else f.path);
          devices = if isServer then f.devices else [ config.me.server ];
          ignorePatterns = defaultPatterns ++ f.ignorePatterns;
          versioning = {
            type = "simple";
            params = {
              keep = "5";
              cleanoutDays = "14";
            };
          };
        }) activeFolders;

        persist.directories = lib.optionals isServer (
          lib.mapAttrsToList (_: f: {
            directory = cfg.dataRoot + f.serverPath;
            user = "syncthing";
            group = "syncthing";
            mode = "0755";
          }) activeFolders
        );

        persistUser.directories = lib.optionals (!isServer) (
          lib.mapAttrsToList (_: f: f.path) activeFolders
        );
      };
    };
}
