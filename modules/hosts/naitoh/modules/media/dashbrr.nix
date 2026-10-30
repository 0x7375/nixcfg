{
  flake.modules.nixos.naitoh =
    {
      pkgs,
      config,
      ...
    }:
    let
      inherit (config.me.services.dashbrr) port;
    in
    {
      me.services.dashbrr = {
        subdomain = "dash";
        port = 11012;
      };

      systemd.tmpfiles.settings.dashbrr."/data/main/.state/dashbrr".d = {
        group = "root";
        user = "root";
        mode = "0755";
      };

      networking.firewall.allowedTCPPorts = [ port ];

      virtualisation.oci-containers.containers.dashbrr =
        let
          name = "ghcr.io/autobrr/dashbrr";
          version = "pr-218";
        in
        {
          image = name + ":" + version;

          imageFile = pkgs.dockerTools.pullImage {
            imageName = name;
            imageDigest = "sha256:4e9dfa6e649c6fcfbed3af332880bf23aefe15f2a705302c2038cabd194d120b";
            sha256 = "sha256-Wzowk6agXp5pPT7LKMHIlO1TzaPU+pydbni47XnpzLM=";

            finalImageTag = version;
          };

          extraOptions = [
            "--add-host=host.docker.internal:host-gateway"
          ];

          volumes = [
            "/data/main/.state/dashbrr/:/data"
          ];

          ports = [ "${toString port}:${toString port}" ];

          environment = {
            TZ = toString config.time.timeZone;
            DASHBRR__LISTEN_ADDR = "0.0.0.0:${toString port}";
            DASHBRR__DB_TYPE = "sqlite";
            DASHBRR__DB_PATH = "/data/dashbrr.db";
            DASHBRR__LOG_LEVEL = "info";
          };
        };
    };
}
