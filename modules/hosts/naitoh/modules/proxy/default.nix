{ self, ... }:

{
  flake.modules.nixos.naitoh =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    let
      inherit (config.me) domain services;

      proxyAuthServices = lib.filterAttrs (_: service: service.proxyAuthSecret != null) services;

      errorPages = {
        "403" = {
          codes = "403";
          title = "Access denied";
          message = "You don't have permission to access this resource.";
          action = "Back to homepage";
          href = "https://${domain}";
        };

        "404" = {
          codes = "404";
          title = "Not found";
          message = "The requested page or service does not exist.";
          action = "Back to homepage";
          href = "https://${domain}";
        };

        "413" = {
          codes = "413";
          title = "Request too large";
          message = "The request exceeds the server's allowed size.";
          action = "Back to homepage";
          href = "https://${domain}";
        };

        "50x" = {
          codes = "500 502 503 504";
          title = "Temporarily unavailable";
          message = "The service may be restarting or experiencing an issue.";
          action = "Retry";
          href = "";
        };
      };

      errorConfig = lib.concatStringsSep "\n" (
        lib.mapAttrsToList (name: page: "error_page ${page.codes} /__errors/${name}.html;") errorPages
      );

      errorLocations = lib.mapAttrs' (
        name: page:
        lib.nameValuePair "= /__errors/${name}.html" {
          alias = "${pkgs.writeText "${name}.html" (
            lib.replaceStrings
              [ "@code@" "@title@" "@message@" "@action@" "@href@" ]
              [ name page.title page.message page.action page.href ]
              (builtins.readFile ./error.html)
          )}";

          extraConfig = ''
            internal;
            add_header Cache-Control "no-store" always;
          '';
        }
      ) errorPages;

      ssoLocations =
        let
          proxyPass = "http://127.0.0.1:4180";

          proxyHeaders = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $remote_addr;
            proxy_set_header X-Forwarded-Host $host;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Uri $request_uri;
          '';
        in
        {
          "/oauth2/" = {
            inherit proxyPass;
            recommendedProxySettings = false;

            extraConfig = proxyHeaders + ''
              proxy_set_header X-Auth-Request-Redirect $request_uri;
            '';
          };

          "= /oauth2/auth" = {
            inherit proxyPass;
            recommendedProxySettings = false;

            extraConfig = proxyHeaders + ''
              internal;
              proxy_pass_request_body off;
              proxy_set_header Content-Length "";
            '';
          };
        };

      ssoConfig = ''
        auth_request /oauth2/auth;
        error_page 401 = /oauth2/start;

        ${errorConfig}
      '';

      mkSubDomain =
        name:
        {
          port ? null,
          root ? null,
          path ? "",
          webSockets ? false,
          extraConfig ? "",
          sso ? false,
          proxyAuthSecret ? null,
          ...
        }:
        {
          forceSSL = true;
          useACMEHost = domain;
          extraConfig = errorConfig;

          locations =
            errorLocations
            // {
              "/" =
                (
                  if root != null then
                    {
                      inherit root;
                    }
                  else
                    {
                      proxyPass = "http://127.0.0.1:${toString port}";
                      proxyWebsockets = webSockets;
                    }
                )
                // {
                  extraConfig =
                    lib.optionalString sso ssoConfig
                    + lib.optionalString (proxyAuthSecret != null) ''
                      include ${config.sops.templates."${name}-auth.conf".path};
                    ''
                    + extraConfig;
                };
            }
            // lib.optionalAttrs (path != "") {
              "= /" = {
                return = "302 /${path}";
              };
            }
            // lib.optionalAttrs sso ssoLocations;
        };

      generatedHtml =
        let
          visible = lib.filterAttrs (_: service: service.visible) config.me.services;
          links = lib.concatStringsSep "\n" (
            lib.mapAttrsToList (name: service: ''<li><a href="${service.url}">${name}</a></li>'') visible
          );
        in
        # html
        ''
          <!DOCTYPE html>
          <html>
            <head>
              <meta charset="utf-8">
              <title>~/homelab</title>
              <style type="text/css">
              ${builtins.readFile ./styles.css}
              </style>
              <link rel="icon" href="./img/tux.png">
            </head>
            <body>
              <h1>~/homelab</h1>

              <div class="marquee-wrap"><span>bonjour &nbsp;&nbsp;&nbsp;&nbsp;·&nbsp;&nbsp;&nbsp;&nbsp; c'est la liste des services en gros &nbsp;&nbsp;&nbsp;&nbsp;·&nbsp;&nbsp;&nbsp;&nbsp; il faut cliquer sur les liens &nbsp;&nbsp;&nbsp;&nbsp;·&nbsp;&nbsp;&nbsp;&nbsp; c'est long là &nbsp;&nbsp;&nbsp;&nbsp;·&nbsp;&nbsp;&nbsp;&nbsp; (salut) </span></div>

              <hr>

              <ul id="services">
                ${links}
              </ul>

              <hr>

              <div class="badge-banner">
                <img src="./img/gnu-linux.gif">
                <img src="./img/neovim.gif">
                <img src="./img/jellyfin.gif">
                <img src="./img/bitwarden.gif">
                <img src="./img/grapheneos.gif">
                <img src="./img/steam.gif">
                <img src="./img/gaywebring.gif">
                <img src="./img/vocaloid.gif">
                <img src="./img/stop.gif">
              </div>
            </body>
          </html>
        '';
    in
    {
      assertions = lib.mapAttrsToList (name: service: {
        assertion = service.sso && service.port != null && service.root == null;
        message = "${name}: proxyAuthSecret requires a proxied service with SSO";
      }) proxyAuthServices;

      networking.firewall.allowedTCPPorts = [
        80
        443
      ];

      systemd.tmpfiles.rules =
        let
          content = builtins.replaceStrings [ "\n" ] [ "\\n" ] generatedHtml;
        in
        [
          "f+ /var/www/index.html 0644 root root - ${content}"
        ];

      services.nginx = {
        enable = true;
        recommendedProxySettings = true;

        virtualHosts = {
          _ = {
            default = true;
            addSSL = true;
            useACMEHost = domain;
            extraConfig = "return 444;";
          };

          "*.${domain}" = {
            forceSSL = true;
            useACMEHost = domain;
            extraConfig = errorConfig;

            locations = errorLocations // {
              "/".return = "404";
            };
          };

          "${domain}" = {
            forceSSL = true;
            enableACME = true;
            extraConfig = errorConfig;

            locations = errorLocations // {
              "/".root = "/var/www";
              "/img/".alias = "${./img}/";
            };
          };

          "router.${domain}" = {
            forceSSL = true;
            useACMEHost = domain;
            extraConfig = errorConfig;

            locations = errorLocations // {
              "/".proxyPass = "http://${config.me.networkIps.gateway}";
            };
          };
        }
        // lib.mapAttrs' (
          name: service: lib.nameValuePair "${service.subdomain}.${domain}" (mkSubDomain name service)
        ) services;
      };

      systemd.services =
        self.lib.notifyOnServiceFailure "nginx" // self.lib.notifyOnServiceFailure "acme-${domain}";

      me.hostSecrets = {
        cloudflare_dns_token = { };
      }
      // lib.mapAttrs' (_: service: lib.nameValuePair service.proxyAuthSecret { }) proxyAuthServices;

      sops.templates = {
        "cloudflare.env".content = ''
          CLOUDFLARE_DNS_API_TOKEN=${config.sops.placeholder.cloudflare_dns_token}
        '';
      }
      // lib.mapAttrs' (
        name: service:
        lib.nameValuePair "${name}-auth.conf" {
          content = ''
            proxy_set_header Authorization "Basic ${config.sops.placeholder.${service.proxyAuthSecret}}";
          '';

          owner = config.services.nginx.user;
          mode = "0400";
        }
      ) proxyAuthServices;

      persist.directories = [ "/var/lib/acme" ];

      security.acme = {
        acceptTerms = true;
        defaults.email = "acme.ranked@0xaa.me";

        certs."${domain}" = {
          extraDomainNames = [ "*.${domain}" ];
          dnsProvider = "cloudflare";
          environmentFile = config.sops.templates."cloudflare.env".path;
          webroot = null;
        };
      };
    };
}
