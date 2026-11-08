{
  flake.modules.nixos.naitoh =
    { config, ... }:
    let
      inherit (config.me.services.attic) port url;
    in
    {
      networking.firewall.allowedTCPPorts = [ port ];

      me.hostSecrets.attic_server_token = { };
      sops.templates."attic.env".content =
        # bash
        ''
          ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=${config.sops.placeholder.attic_server_token}
        '';

      persist.directories = [ "/var/lib/private/atticd" ];

      services.atticd = {
        enable = true;
        environmentFile = config.sops.templates."attic.env".path;
        settings = {
          listen = "[::]:${toString port}";
          api-endpoint = url + "/";
          jwt = { };

          chunking = {
            nar-size-threshold = 64 * 1024;
            min-size = 16 * 1024;
            avg-size = 256 * 1024;
            max-size = 256 * 1024;
          };

          garbage-collection = {
            default-retention-period = "6 months";
          };
        };
      };
    };
}
