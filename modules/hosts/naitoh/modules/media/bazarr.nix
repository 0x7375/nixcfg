{
  flake.modules.nixos.naitoh =
    {
      config,
      pkgs,
      ...
    }:
    {
      me.services.bazarr = {
        subdomain = "subtitles";
        port = config.services.bazarr.listenPort;
      };

      services.bazarr = {
        enable = true;
        group = config.me.mediaGroup;
        dataDir = "/data/main/.state/bazarr";

        # TODO: use mv.latest once that version is upstreamed (oidc support)
        package = pkgs.bazarr.overrideAttrs (
          final: prev: {
            version = "1.6.3-beta.38";

            src = pkgs.fetchFromGitHub {
              owner = "morpheus65535";
              repo = "bazarr";
              tag = "v${final.version}";
              hash = "sha256-JAWdp78Uq8T1yW/Thoo9N9mamF8SxdNzkekLOYj0+WU=";
            };

            patches = [ ];

            postPatch =
              let
                release = pkgs.fetchzip {
                  url = "https://github.com/morpheus65535/bazarr/releases/download/v${final.version}/bazarr.zip";
                  hash = "sha256-MwQrXbuBBWDjw69DnBafdOAoGxmmfG4ghVA8rP5bcRI=";
                  stripRoot = false;
                };
              in
              (prev.postPatch or "")
              + ''
                mkdir -p frontend/build
                cp -r ${release}/frontend/build/. frontend/build/
              '';
          }
        );
      };

      me.hostSecrets."oidc/bazarr".owner = config.services.bazarr.user;

      systemd.services.bazarr = {
        serviceConfig.UMask = "0002";

        environment = {
          DYNACONF_general__ip = ''@json "127.0.0.1"'';
          DYNACONF_auth__type = "oidc";
          DYNACONF_auth__oidc_issuer = config.me.services.pocket-id.url;
          DYNACONF_auth__oidc_client_id = "ecbddea8-3b67-4ddf-ad5d-b7db39cbfeeb";
          DYNACONF_auth__oidc_redirect_uri = "${config.me.services.bazarr.url}/auth/oidc/callback";
          DYNACONF_auth__oidc_allowed_subjects = ''@json ["${config.me.oidcSubject}"]'';
          DYNACONF_auth__oidc_client_secret_file = config.sops.secrets."oidc/bazarr".path;
        };
      };
    };
}
