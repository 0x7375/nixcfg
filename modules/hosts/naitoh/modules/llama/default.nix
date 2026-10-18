{
  flake.modules.nixos.naitoh =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.me.services.llama) port;
      pkg = pkgs.auto.llama-cpp-vulkan;
      backPort = 8089;

      brave-search-mcp = pkgs.buildNpmPackage rec {
        pname = "brave-search-mcp-server";
        version = "2.1.4";
        src = pkgs.runCommand "brave-search-mcp-server-src" { } ''
          cp -r ${
            pkgs.fetchFromGitHub {
              owner = "brave";
              repo = "brave-search-mcp-server";
              rev = "v${version}";
              hash = "sha256-K6BOxpPu1mJq4SzMos2Xy13mIlXDN05XAQiOYL22mf8=";
            }
          } $out
          chmod -R u+w $out
          cp ${./brave-package-lock.json} $out/package-lock.json
        '';
        npmDepsFetcherVersion = 2;
        npmDepsHash = "sha256-ODiK9Q0ip0Smenccprg9KpUJhIJk4Ef1t/KfcoGxjrI=";
      };

      mcpConfig = pkgs.writeText "mcp-servers.json" (
        builtins.toJSON {
          mcpServers = {
            # searxng = {
            #   command = lib.getExe pkgs.auto.mcp-searxng;
            #   env.SEARXNG_URL = "http://127.0.0.1:8888";
            # };
            brave.command = lib.getExe (
              pkgs.writeShellApplication {
                name = "brave-mcp";
                text = ''
                  BRAVE_API_KEY=$(cat /run/credentials/llama-server.service/brave-key)
                  export BRAVE_API_KEY
                  exec ${brave-search-mcp}/bin/brave-search-mcp-server
                '';
              }
            );
            nixos.command = lib.getExe pkgs.mcp-nixos;
            fetch.command = lib.getExe pkgs.mcp-server-fetch;

            time.command = lib.getExe pkgs.mcp-server-time;
            github.command = lib.getExe (
              pkgs.writeShellApplication {
                name = "github-mcp";
                text = ''
                  GITHUB_PERSONAL_ACCESS_TOKEN=$(cat /run/credentials/llama-server.service/github-token)
                  export GITHUB_PERSONAL_ACCESS_TOKEN
                  exec ${lib.getExe pkgs.github-mcp-server} stdio
                '';
              }
            );
            pdf.command = lib.getExe pkgs.auto.pdf-mcp;

            filesystem = {
              command = lib.getExe pkgs.mcp-server-filesystem;
              args = [ "/var/lib/llama-server/workspace" ];
            };
          };
        }
      );
    in
    {
      me.services.llama = {
        subdomain = "ai";
        port = 8088;
        webSockets = true;
        extraConfig = ''
            proxy_set_header Accept-Encoding "";
            proxy_read_timeout 1h;

            sub_filter '<head>' '<head><script src="/__sync.js"></script>';
            sub_filter_once on;
          }

          location = /__sync.js {
            alias ${./chat-sync.js};
            default_type application/javascript;
            add_header Cache-Control "no-store";
          }

          location /models/sse {
            proxy_pass http://127.0.0.1:${toString backPort};
            proxy_http_version 1.1;
            proxy_set_header Connection "";
            proxy_read_timeout 1h;
            proxy_buffering off;
            proxy_cache off;
          }

          location = /__chats.json {
            root /var/lib/nginx;
            dav_methods PUT;
            create_full_put_path on;
            dav_access user:rw group:r all:r;
            client_max_body_size 50M;
            client_body_temp_path /var/lib/nginx;
            default_type application/json;
            add_header Cache-Control "no-store";
        '';
      };

      services.nginx.appendHttpConfig = ''
        server {
          listen 127.0.0.1:${toString port};
          location / {
            proxy_pass http://127.0.0.1:${toString backPort};
            proxy_http_version 1.1;
            proxy_set_header Accept-Encoding "gzip";
            proxy_set_header Host $host;
            proxy_buffering off;
            proxy_read_timeout 1h;
            gunzip on;
          }
        }
      '';

      # services.searx = {
      #   enable = true;
      #   redisCreateLocally = true;
      #   settings = {
      #     server = {
      #       bind_address = "127.0.0.1";
      #       port = 8888;
      #       secret_key = "local-ai-searxng-secret";
      #     };
      #     search.formats = [
      #       "html"
      #       "json"
      #     ];
      #     engines = lib.mapAttrsToList (name: value: { inherit name; } // value) {
      #       "duckduckgo".disabled = false;
      #       "startpage".disabled = false;
      #       "brave".disabled = true;
      #       "qwant".disabled = false;
      #       "yahoo".disabled = false;
      #       "google".disabled = false;
      #       "bing".disabled = false;
      #       "mojeek".disabled = false;
      #       "wikipedia".disabled = false;
      #     };
      #   };
      # };

      systemd.services.nginx.serviceConfig.ReadWritePaths = [ "/var/lib/nginx" ];

      packages = [ pkg ];

      persist.directories = [
        "/var/lib/private/llama-server"
        {
          directory = "/var/lib/nginx";
          user = "nginx";
          group = "nginx";
          mode = "0755";
        }
      ];

      me.hostSecrets.brave_api_key = { };

      systemd.services.llama-server = {
        description = "Llama.cpp Web Server";
        after = [
          "network.target"
          "searx-init.service"
        ];
        wantedBy = [ "multi-user.target" ];
        environment = {
          HOME = "/var/lib/llama-server";
          SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
        };

        preStart = ''
          mkdir -p /var/lib/llama-server/models
        '';

        serviceConfig = {
          LoadCredential = [
            "github-token:${config.sops.secrets.github_token.path}"
            "brave-key:${config.sops.secrets.brave_api_key.path}"
          ];
          ExecStart = ''
            ${lib.getExe' pkg "llama-server"} \
              --models-dir /var/lib/llama-server/models \
              --models-max 1 \
              --host 127.0.0.1 \
              --port ${toString backPort} \
              --ctx-size 16384 \
              --jinja \
              --webui-mcp-proxy \
              --cors-origins "${config.me.services.llama.url}" \
              --mcp-servers-config ${mcpConfig} \
              -t 6
          '';
          Restart = "always";
          RestartSec = 5;
          DynamicUser = true;
          StateDirectory = "llama-server";
          WorkingDirectory = "/var/lib/llama-server";
          SupplementaryGroups = [
            "video"
            "render"
          ];
        };
      };
    };
}
