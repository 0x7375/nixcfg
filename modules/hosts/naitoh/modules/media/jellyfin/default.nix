{
  flake.modules.nixos.naitoh =
    {
      mv,
      pkgs,
      config,
      ...
    }:
    {
      me.services.jellyfin = {
        subdomain = "media";
        port = config.nixflix.jellyfin.network.publicHttpPort;
        webSockets = true;
      };

      hardware.graphics = {
        enable = true;
        extraPackages = with pkgs; [
          rocmPackages.clr
          rocmPackages.clr.icd
        ];
      };

      persist.directories = [
        {
          directory = "/var/cache/jellyfin";
          user = "jellyfin";
          group = "media";
        }
        {
          directory = "/var/lib/jellyfin";
          user = "jellyfin";
          group = "media";
        }
      ];

      users.users.jellyfin.extraGroups = [
        "render"
        "video"
      ];

      me.hostSecrets."jellyfin/api_key" = { };
      me.hostSecrets."jellyfin/admin_pw" = { };
      me.hostSecrets."jellyfin/user_pw" = { };

      # high priority under load
      systemd.services.jellyfin.serviceConfig = {
        CPUWeight = 200;
        IOWeight = 200;
        IOSchedulingClass = "best-effort";
        IOSchedulingPriority = 2;
      };

      me.hostSecrets."oidc/jellyfin".owner = config.services.jellyfin.user;

      nixflix.jellyfin =
        let
          abyss = pkgs.fetchFromGitHub {
            owner = "AumGupta";
            repo = "abyss-jellyfin";
            tag = "v1.2.3";
            hash = "sha256-tzXgVk1HKiBi5BAibD8LjJ/qTBEEGZjDEpV1LIOyeVg=";
          };

          jellyfinWeb = pkgs.runCommand "jellyfin-web-abyss" { } ''
            mkdir -p "$out/share"
            cp -a ${mv.latest.jellyfin-web.out}/share/jellyfin-web "$out/share/"

            webDir="$out/share/jellyfin-web"
            chmod -R u+w "$webDir"

            mkdir -p "$webDir/ui"

            cp ${abyss}/scripts/spotlight/spotlight.html "$webDir/ui/"
            cp ${abyss}/scripts/spotlight/spotlight.css "$webDir/ui/"

            target=$(find "$webDir" -maxdepth 1 -name 'home-html.*.chunk.js' -print -quit)

            if [ -n "$target" ]; then
              cp ${abyss}/scripts/spotlight/home-html.chunk.js "$target"
            else
              echo "ERROR: home-html chunk not found in $webDir" >&2
              exit 1
            fi
          '';

          jellyfinPackage =
            pkgs.runCommand "jellyfin"
              {
                inherit (mv.latest.jellyfin) version;
                meta.mainProgram = "jellyfin";
              }
              ''
                mkdir -p "$out/bin"

                cp ${mv.latest.jellyfin.out}/bin/jellyfin "$out/bin/jellyfin"
                chmod u+w "$out/bin/jellyfin"

                if ! grep -q -- '--webdir=' "$out/bin/jellyfin"; then
                  echo "ERROR: Jellyfin wrapper has no --webdir argument" >&2
                  exit 1
                fi

                sed -i \
                  's|--webdir=[^ ]*|--webdir=${jellyfinWeb}/share/jellyfin-web|' \
                  "$out/bin/jellyfin"
              '';
        in
        {
          enable = true;
          package = jellyfinPackage;

          libraries =
            let
              common = {
                enableChapterImageExtraction = false;
                enableTrickplayImageExtraction = false;
              };
            in
            {
              Movies = common;
              Shows = common;
            };

          users.seerr = {
            password._secret = config.sops.secrets."jellyfin/admin_pw".path;
            policy = {
              isAdministrator = true;
              isHidden = true;
              enableRemoteAccess = false;
            };
          };

          system.enableGroupingMoviesIntoCollections = true;

          branding = {
            loginDisclaimer =
              # html
              ''
                <div id="oidc-sso-buttons">
                  <a class="oidc-sso-btn" href="/sso/OIDC/Start/pocketid">
                    <span>Pocket ID</span>
                  </a>
                </div>
              '';

            customCss = builtins.readFile ./style.css;
          };

          users.${config.me.user}.password._secret = config.sops.secrets."jellyfin/user_pw".path;
          apiKey._secret = config.sops.secrets."jellyfin/api_key".path;

          encoding = {
            hardwareAccelerationType = "vaapi";
            allowHevcEncoding = true;
            hardwareDecodingCodecs = [
              "h264"
              "hevc"
              "mpeg2video"
              "vc1"
              "vp8"
              "vp9"
            ];
            enableTonemapping = true;
            enableEnhancedNvdecDecoder = false;
          };

          plugins."SSO-OIDC-Authentication" = {
            enable = true;

            config = {
              Providers = [
                {
                  ProviderId = "pocketid";
                  DisplayName = "Pocket ID";
                  Authority = config.me.services.pocket-id.url;
                  ClientId = "7a750fe8-d028-49f8-8e7a-3775565f610a";
                  ClientSecretFile = config.sops.secrets."oidc/jellyfin".path;
                  Scopes = "openid profile groups";
                  RoleClaim = "groups";
                  UsernameClaim = "preferred_username";
                  Enabled = true;
                }
              ];

              ServerBaseUrl = config.me.services.jellyfin.url;

              AutoCreateUsers = true;
              MigrateLocalUsers = true;

              AllowedGroups = [
                "admin"
                "user"
              ];

              ManageLoginButtonBranding = false;
              HideManualLogin = true;
              LoginTitle = "";
              LoginSubtitle = "";

              RoleMappings = [
                {
                  RoleName = "admin";
                  IsAdmin = true;
                  EnableAllLibraries = true;

                  EnableContentDeletion = true;
                  EnableCollectionManagement = true;
                  EnableSubtitleManagement = true;
                }
                {
                  RoleName = "user";
                  IsAdmin = false;
                  EnableAllLibraries = true;
                }
              ];
            };
          };
        };
    };
}
