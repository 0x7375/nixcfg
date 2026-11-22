{
  flake.modules.nixos.naitoh =
    {
      pkgs,
      config,
      ...
    }:
    {
      me.services.cleanuparr = {
        subdomain = "cleanup";
        port = 11011;
        webSockets = true;
      };

      systemd.tmpfiles.settings.cleanuparr."/data/main/.state/cleanuparr".d = {
        group = "root";
        user = "root";
        mode = "0755";
      };

      virtualisation.oci-containers.containers.cleanuparr =
        let
          name = "ghcr.io/cleanuparr/cleanuparr";
          version = "2.11.1";
        in
        {
          image = name + ":" + version;

          imageFile = pkgs.dockerTools.pullImage {
            imageName = name;
            imageDigest = "sha256:923c2fe435e22fc58d261bacd2d6bbd8eb1ba3f95358803a8e4d3287ffd919d3";
            sha256 = "sha256-SBIN44URd7cwTCxa3gPgCe4hTnmejmlGMjUElwr19DI=";

            finalImageTag = version;
          };

          extraOptions = [ "--network=host" ];

          volumes = [
            "/data/main/.state/cleanuparr/:/config"
          ];

          environment = {
            TZ = toString config.time.timeZone;
            PUID = "0";
            PGID = "0";
          };
        };
    };
}
