{
  flake.modules.nixos.custom =
    { config, lib, ... }:
    let
      parentConfig = config;
      inherit (lib) mkEnableOption mkOption types;
      serviceSubmodule =
        { config, ... }:
        {
          options = {
            subdomain = mkOption {
              type = types.str;
              description = "Network subdomain";
            };

            port = mkOption {
              type = types.nullOr types.int;
              default = null;
              description = "Network port for a proxied service";
            };

            root = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "Document root for a static service";
            };

            path = mkOption {
              type = types.str;
              default = "";
              description = "Path appended to the url";
            };

            url = mkOption {
              type = types.str;
              readOnly = true;
              default = "https://${config.subdomain}.${parentConfig.me.domain}${
                lib.optionalString (config.path != "") "/" + config.path
              }";
              description = "Constructed public URL for this service";
            };

            webSockets = mkEnableOption "Enable websocket proxying";

            extraConfig = mkOption {
              type = types.lines;
              default = "";
              description = "Extra configuration passed to nginx";
            };
          };
        };
    in
    {
      options.me = {
        domain = mkOption {
          type = types.str;
          default = "0xaa.me";
          description = "My domain name";
        };

        vpnPort = mkOption {
          type = types.int;
          default = 19598;
          description = "VPN Forwarded port";
        };

        services = mkOption {
          description = "Central server services definition";
          internal = true;
          type = types.attrsOf (types.submodule serviceSubmodule);
        };
      };

      config.me.services = {
        radicale = {
          subdomain = "calendar";
          port = 5232;
        };
        attic = {
          subdomain = "cache";
          port = 8082;
          extraConfig = ''
            client_max_body_size 0;
          '';
        };
      };
    };
}
