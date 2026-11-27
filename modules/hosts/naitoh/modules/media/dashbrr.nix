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

      me.hostSecrets."oidc/dashbrr" = { };

      sops.templates."dashbrr.env".content = ''
        DASHBRR__OIDC_CLIENT_SECRET=${config.sops.placeholder."oidc/dashbrr"}
      '';

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

          extraOptions = [ "--network=host" ];

          volumes = [
            "/data/main/.state/dashbrr/:/data"
          ];

          environmentFiles = [
            config.sops.templates."dashbrr.env".path
          ];

          environment = {
            TZ = toString config.time.timeZone;
            DASHBRR__LISTEN_ADDR = "127.0.0.1:${toString port}";
            DASHBRR__DB_TYPE = "sqlite";
            DASHBRR__DB_PATH = "/data/dashbrr.db";
            DASHBRR__LOG_LEVEL = "info";

            DASHBRR__OIDC_ISSUER = config.me.services.pocket-id.url;
            DASHBRR__OIDC_CLIENT_ID = "54abc19b-03fe-49e5-aabc-4af37dc3090f";
            DASHBRR__OIDC_REDIRECT_URL = "${config.me.services.dashbrr.url}/api/auth/oidc/callback";
          };
        };
    };
}
