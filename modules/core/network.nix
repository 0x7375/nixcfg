{ self, ... }:

{
  flake.modules.generic.network =
    { config, lib, ... }:
    {
      environment.etc.hosts.text =
        let
          hosts = lib.flatten (
            lib.mapAttrsToList (h: v: (lib.optional (v.ip != null) "${v.ip} ${h}")) config.me.hosts
          );
        in
        lib.mkForce ''
          127.0.0.1 localhost
          255.255.255.255 broadcasthost
          ::1 localhost
          ${builtins.concatStringsSep "\n" hosts}
          192.168.1.86 hilse
        '';
    };

  flake.modules.darwin.network =
    {
      lib,
      ...
    }:
    {
      preActivation = "rm -f /etc/hosts";

      networking.dns = [
        "127.0.0.1"
        "::1"
      ];

      # https://github.com/cameronraysmith/vanixiets/blob/0f5f3018b628bc287a4b6339553180c696c233dc/modules/darwin/dnscrypt-proxy.nix#L188
      services.dnscrypt-proxy = {
        enable = true;
        settings = {
          listen_addresses = [
            "127.0.0.1:53"
            "[::1]:53"
          ];

          server_names = [
            # "aquilenet"
            "fdn-ns0"
            "fdn-ns1"
          ];

          ipv4_servers = true;
          dnscrypt_servers = false;
          doh_servers = true;

          require_dnssec = true;
          require_nolog = true;
          require_nofilter = true;

          lb_strategy = "first";

          bootstrap_resolvers = [ ];
          ignore_system_dns = true;
          # netprobe_address = "45.67.81.23:443";
          netprobe_address = "80.67.169.12:443";

          cache = true;
          cache_size = 4096;

          static = {
            # "aquilenet".stamp = "sdns://AgcAAAAAAAAACzQ1LjY3LjgxLjIzABBkbnMuYXF1aWxlbmV0LmZyCi9kbnMtcXVlcnk";
            "fdn-ns0".stamp = "sdns://AgcAAAAAAAAADDgwLjY3LjE2OS4xMgAKbnMwLmZkbi5mcgovZG5zLXF1ZXJ5";
            "fdn-ns1".stamp = "sdns://AgcAAAAAAAAADDgwLjY3LjE2OS40MAAKbnMxLmZkbi5mcgovZG5zLXF1ZXJ5";
          };
        };
      };

      launchd.daemons.dnscrypt-proxy.serviceConfig = {
        UserName = lib.mkForce "root";
        GroupName = lib.mkForce "wheel";
      };

      users.users._dnscrypt-proxy.home = lib.mkForce "/var/lib/dnscrypt-proxy";

      networking.knownNetworkServices = [
        "Wi-Fi"
        "USB 10/100 LAN"
        "Thunderbolt Bridge"
      ];
    };

  flake.modules.nixos.network =
    { lib, config, ... }:
    {
      persist.directories = [
        {
          directory = "/etc/NetworkManager/system-connections";
          mode = "0700";
        }
      ];

      imports = [ self.modules.generic.network ];

      networking.nameservers = [
        # Aquilenet
        # "45.67.81.23#dns.aquilenet.fr"
        # "2a0c:e300::1337#dns.aquilenet.fr"

        # FDN
        "80.67.169.12#ns0.fdn.fr"
        "80.67.169.40#ns1.fdn.fr"
        "2001:910:800::12#ns0.fdn.fr"
        "2001:910:800::40#ns1.fdn.fr"
      ];

      services.resolved = {
        enable = true;
        settings = {
          Resolve = {
            DNSOverTLS = "true";
            DNSSEC = "true";
            Domains = [ "~." ];
            FallbackDNS = [ ];
          };
        };
      };

      networking.firewall.allowedUDPPorts = [ 5353 ];

      systemd.services.systemd-resolved.serviceConfig.LogLevelMax = "notice";

      # Configure network proxy if necessary
      # networking.proxy.default = "http://user:password@proxy:port/";
      # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";
      networking.networkmanager = {
        enable = true;
        dns = "systemd-resolved";
      };

      users.users.${config.me.user}.extraGroups = [ "networkmanager" ];

      # don't wait for network on boot
      systemd.services.NetworkManager-wait-online.wantedBy = lib.mkForce [ ];

      networking.nftables.enable = true;
      networking.firewall.enable = true;
    };

  # asahi moment
  flake.modules.nixos.woz.networking.networkmanager.ensureProfiles.profiles.bell.connection.interface-name =
    "wld0";

  flake.modules.nixos.networkEnvironment =
    {
      config,
      secrets,
      ...
    }:
    {
      imports = [ self.modules.nixos.network ];

      sops.secrets.networkingEnvironment = {
        sopsFile = "${secrets}/networking-environment.env";
        format = "dotenv";
        key = "";
        owner = config.me.user;
      };

      networking.networkmanager.ensureProfiles = {
        environmentFiles = [ config.sops.secrets.networkingEnvironment.path ];
        profiles =
          let
            ignoreDns = {
              ipv4 = {
                method = "auto";
                ignore-auto-dns = true;
              };
              ipv6 = {
                method = "auto";
                ignore-auto-dns = true;
              };
            };
          in
          {
            home-wifi = {
              connection = {
                id = "home-wifi";
                type = "wifi";
              };
              wifi = {
                ssid = "$SSID_HOME";
              };
              wifi-security = {
                key-mgmt = "wpa-psk";
                psk = "$PSK_HOME";
              };
            }
            // ignoreDns;
            bell = {
              connection = {
                id = "bell";
                type = "wifi";
              };
              wifi = {
                mode = "infrastructure";
                ssid = "bell";
              };
              wifi-security = {
                key-mgmt = "wpa-psk";
                psk = "$PSK_BELL";
              };
            }
            // ignoreDns;
            away_1 = {
              connection = {
                id = "away_1";
                type = "wifi";
              };
              wifi = {
                ssid = "$SSID_AWAY_1";
              };
              wifi-security = {
                key-mgmt = "wpa-psk";
                psk = "$PSK_AWAY_1";
              };
            }
            // ignoreDns;
            away_2 = {
              connection = {
                id = "away_2";
                type = "wifi";
              };
              wifi = {
                ssid = "$SSID_AWAY_2";
              };
              wifi-security = {
                key-mgmt = "wpa-psk";
                psk = "$PSK_AWAY_2";
              };
            }
            // ignoreDns;
            eduroam = {
              "802-1x" = {
                anonymous-identity = "anonymous@unicaen.fr";
                eap = "ttls;";
                identity = "$USER_EDUROAM";
                password = "$PSK_EDUROAM";
                phase2-auth = "mschapv2";
              };
              connection = {
                id = "eduroam";
                type = "wifi";
              };
              wifi = {
                mode = "infrastructure";
                ssid = "eduroam";
              };
              wifi-security = {
                auth-alg = "open";
                key-mgmt = "wpa-eap";
              };
            }
            // ignoreDns;
          };
      };
    };
}
