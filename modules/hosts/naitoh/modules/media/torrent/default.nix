{ self, ... }:

{
  flake.modules.nixos.naitoh =
    {
      lib,
      mv,
      config,
      pkgs,
      ...
    }:
    let
      template = "@guiPassword@";
    in
    {
      me.services = {
        qbittorrent = {
          subdomain = "qbittorrent";
          port = config.nixflix.torrentClients.qbittorrent.webuiPort;
          sso = true;
          proxyAuthSecret = "qbittorrent/basic_auth";
        };
        qui = {
          subdomain = "torrent";
          inherit (config.services.qui.settings) port;
          path = "instances/1";
        };
      };

      me.hostSecrets."qbittorrent/pw_hash".owner = config.services.qbittorrent.user;
      me.hostSecrets."qbittorrent/pw".owner = config.services.qbittorrent.user;

      nixflix.torrentClients.qbittorrent = {
        enable = true;
        password._secret = config.sops.secrets."qbittorrent/pw".path;
        package = self.lib.withMainProgram "qbittorrent-nox" mv.latest.qbittorrent-nox;
        profileDir = "/data/main/.state/qBittorrent";
        serverConfig = {
          LegalNotice.Accepted = true;
          AutoRun = {
            OnTorrentAdded = {
              Enabled = true;
              Program = "systemctl start wg-quick-airvpn";
            };
          };
          BitTorrent = {
            ExcludedFileNamesEnabled = true;
            Session = {
              BTProtocol = "TCP";
              Port = config.me.vpnPort;
              DisableAutoTMMByDefault = false;
              DisableAutoTMMTriggers = {
                CategorySavePathChanged = false;
                DefaultSavePathChanged = false;
              };
              ExcludedFileNames = builtins.readFile ./blacklist.txt;
              Interface = "airvpn";
              Preallocation = true;
              QueueingSystemEnabled = false;
              PeXEnabled = true;
              DHTEnabled = true;
            };
          };
          Preferences = {
            Connection.ResolvePeerCountries = false;
            WebUI = {
              Address = "127.0.0.1";
              LocalHostAuth = true;
              AuthSubnetWhitelistEnabled = false;
              Username = "admin";
              Password_PBKDF2 = "@ByteArray(${template})";
              CSRFProtection = true;
              ClickjackingProtection = true;
              MaxAuthenticationFailCount = 10;
            };
            General.Locale = "en";
          };
          Network = {
            PortForwardingEnabled = false;
          };
        };
      };

      me.hostSecrets.qui_session.owner = config.services.qbittorrent.user;

      systemd.services.qbittorrent = {
        serviceConfig = {
          # low priority under load
          CPUWeight = 50;
          IOWeight = 50;
          IOSchedulingClass = "best-effort";
          IOSchedulingPriority = 6;

          # necessary for polkit rule to work
          RestrictAddressFamilies = lib.mkForce [
            "AF_INET"
            "AF_INET6"
            "AF_NETLINK"
            "AF_UNIX"
          ];

          ExecStartPre = lib.mkAfter [
            (pkgs.writeShellScript "qbittorrent-patch-password" ''
              secret=$(cat "${config.sops.secrets."qbittorrent/pw_hash".path}")
              configFile=${config.services.qbittorrent.profileDir}/qBittorrent/config/qBittorrent.conf

              if [[ -f $configFile ]]; then
                ${lib.getExe' pkgs.gnused "sed"} -i "s#${template}#$secret#" "$configFile"
              fi
            '')
          ];
        };
      };

      services.qui = {
        enable = true;
        user = config.services.qbittorrent.user;
        package = self.lib.withMainProgram "qui" mv.latest.qui;
        group = config.services.qbittorrent.group;
        secretFile = config.sops.secrets.qui_session.path;
        settings.host = "127.0.0.1";
      };

      me.hostSecrets."oidc/qui".owner = config.services.qbittorrent.user;

      systemd.services.qui = {
        after = [ "qbittorrent.service" ];
        requires = [ "qbittorrent.service" ];

        environment = {
          QUI__DATA_DIR = "${config.nixflix.torrentClients.qbittorrent.profileDir}/qui";
          QUI__CHECK_FOR_UPDATES = "false";
          HOME = config.nixflix.torrentClients.qbittorrent.profileDir;
          XDG_CONFIG_HOME = config.nixflix.torrentClients.qbittorrent.profileDir;

          QUI__OIDC_ENABLED = "true";
          QUI__OIDC_ISSUER = config.me.services.pocket-id.url;
          QUI__OIDC_CLIENT_ID = "481dafb4-3606-4db5-88a6-97e9ded743cc";
          QUI__OIDC_CLIENT_SECRET_FILE = config.sops.secrets."oidc/qui".path;
          QUI__OIDC_REDIRECT_URL = "${config.me.services.qui.baseUrl}/api/auth/oidc/callback";
          QUI__OIDC_DISABLE_BUILT_IN_LOGIN = "true";
          QUI__OIDC_ALLOWED_SUBJECT = config.me.oidcSubject;
        };
      };

      security.polkit.extraConfig =
        # js
        ''
          polkit.addRule(function(action, subject) {
            if (action.id == "org.freedesktop.systemd1.manage-units" &&
                action.lookup("unit") == "wg-quick-airvpn.service" &&
                subject.user == "${config.services.qbittorrent.user}") {
              return polkit.Result.YES;
            }
          });
        '';
    };
}
