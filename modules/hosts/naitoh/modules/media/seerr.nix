{ self, ... }:

{
  flake.modules.nixos.naitoh =
    {
      config,
      lib,
      pkgs,
      options,
      ...
    }:
    let
      seerr = pkgs.seerr.overrideAttrs (
        final: old: {
          version = "3.5.2-oidc";

          src = pkgs.fetchFromGitHub {
            owner = "michaelhthomas";
            repo = "seerr";
            rev = "0aa680565233bcfd67bfa4bce5b12f9f89f134da";
            hash = "sha256-VZN6C02nVuF6tunTLQhDYF+nYS99jZlP/uywXRdkwZ4=";
          };

          pnpmDeps = old.pnpmDeps.overrideAttrs {
            inherit (final) src;
            outputHash = "sha256-gqjz0DM0VYdFKTkoKPG9fjAwZlKeQZS1GB4wwUcwZ9M=";
          };
        }
      );
    in
    {
      me.services.seerr = {
        subdomain = "request";
        port = config.nixflix.seerr.port;
      };

      me.hostSecrets."seerr/api_key" = { };
      me.hostSecrets."oidc/seerr" = { };

      systemd.services.seerr = {
        serviceConfig.LoadCredential = [
          "oidc_client_secret:${config.sops.secrets."oidc/seerr".path}"
        ];

        preStart = ''
          settings="${config.nixflix.seerr.dataDir}/settings.json"

          if [ ! -s "$settings" ]; then
            CONFIG_DIRECTORY="${config.nixflix.seerr.dataDir}" \
              ${lib.getExe pkgs.nodejs-slim_22} -e '
                require("${seerr}/share/dist/lib/settings")
                  .getSettings().save().catch(() => process.exit(1))
              '
          fi

          tmp=$(mktemp "$settings.XXXXXX")

          ${lib.getExe pkgs.jq} \
            --rawfile secret "$CREDENTIALS_DIRECTORY/oidc_client_secret" \
            '
              .main.oidcLogin = true |
              .oidc.providers = [{
                slug: "pocketid",
                name: "Pocket ID",
                issuerUrl: "${config.me.services.pocket-id.url}",
                clientId: "aab2b354-0692-4e44-91b7-02cffafbaadf",
                clientSecret: ($secret | rtrimstr("\n")),
                scopes: "openid profile email",
                newUserLogin: true
              }]
            ' "$settings" > "$tmp"

          mv "$tmp" "$settings"
        '';
      };

      systemd.services.seerr-jellyfin = {
        after = [ "jellyfin.service" ];
        requires = [ "jellyfin.service" ];
      };

      nixflix = {
        seerr = {
          enable = true;
          package = self.lib.withMainProgram "seerr" seerr;
          apiKey._secret = config.sops.secrets."seerr/api_key".path;

          jellyfin = {
            adminUsername = "seerr";
            adminPassword._secret = config.sops.secrets."jellyfin/admin_pw".path;
            externalHostname = config.me.services.jellyfin.url;
            enableAllLibraries = true;
          };

          radarr = lib.recursiveUpdate options.nixflix.seerr.radarr.default {
            Radarr = {
              externalUrl = config.me.services.radarr.url;
              syncEnabled = true;
            };
          };

          sonarr = lib.recursiveUpdate options.nixflix.seerr.sonarr.default {
            Sonarr = {
              externalUrl = config.me.services.sonarr.url;
              syncEnabled = true;
            };
          };

          settings.users = {
            localLogin = false;
            mediaServerLogin = false;
            newPlexLogin = false;
            defaultPermissions = 160;
          };
        };

        notif.ntfy.seerr = {
          enable = true;
          serverUrl = "http://127.0.0.1:${toString config.me.services.ntfy.port}";
          accessToken._secret = config.sops.secrets."ntfy/token".path;
          topics = [ "media" ];
          embedPoster = true;

          onMediaAvailable = true;
          onMediaApproved = false;
          onMediaAutoApproved = false;
          onMediaAutoRequested = false;
          onMediaDeclined = false;
          onMediaFailed = false;
          onMediaPending = false;

          onIssueComment = false;
          onIssueCreated = false;
          onIssueReopened = false;
          onIssueResolved = false;
        };
      };

      systemd.services.seerr-oidc-admin = {
        wantedBy = [ "multi-user.target" ];
        after = [ "seerr-setup.service" ];
        requires = [ "seerr-setup.service" ];
        partOf = [ "seerr-setup.service" ];

        serviceConfig = {
          Type = "oneshot";
          User = "postgres";
          RemainAfterExit = true;
        };

        script = ''
          ${config.services.postgresql.package}/bin/psql \
            -d seerr -v ON_ERROR_STOP=1 <<'SQL'
            BEGIN;

            INSERT INTO linked_accounts (provider, sub, username, "userId")
            SELECT 'pocketid', '${config.me.oidcSubject}', 'admin', id
            FROM "user"
            WHERE id = 1
            ON CONFLICT (provider, sub) DO NOTHING;

            UPDATE "user"
            SET permissions = permissions | 2
            WHERE id IN (
              SELECT "userId" FROM linked_accounts
              WHERE provider = 'pocketid'
                AND sub = '${config.me.oidcSubject}'
            );

            COMMIT;
          SQL
        '';
      };
    };
}
