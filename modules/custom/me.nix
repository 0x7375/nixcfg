{
  flake.modules.generic.custom =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.me;
      inherit (lib) mkOption types;
    in
    {
      options.me = {
        flakeDir = mkOption {
          type = types.str;
          default = "/home/${cfg.user}/.config/nixcfg";
          description = "Path to the nixos flake directory";
        };

        home = mkOption {
          type = types.str;
          default = "/home/${cfg.user}";
          description = "Home directory";
        };

        user = mkOption {
          type = types.str;
          default = "ayko";
          description = "User name";
        };

        server = mkOption {
          type = types.str;
          default = "naitoh";
          description = "Server hostname";
        };

        uid = mkOption {
          type = types.int;
          default = 1000;
          description = "User id";
        };

        hostname = mkOption {
          type = types.str;
          default = config.networking.hostName;
          description = "System hostname";
        };

        networkIps = mkOption {
          type = types.attrsOf (types.either types.str (types.attrsOf types.str));
          default = {
            subnet = "192.168.1.0/24";
            gateway = "192.168.1.254";
          };
          internal = true;
        };
      };
    };
}
