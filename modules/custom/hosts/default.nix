{
  flake.modules.generic.custom =
    {
      config,
      lib,
      ...
    }:
    let
      cfg = config.me;
      inherit (lib) mkOption types;

      mkNullOption =
        description:
        mkOption {
          type = types.nullOr types.str;
          default = null;
          inherit description;
        };

      hostSubmodule =
        { config, ... }:
        {
          options = {
            securityKey = {
              name = mkOption {
                type = types.enum [
                  "main"
                  "backup"
                ];
                default = "main";
              };
              fido2Path = mkOption {
                type = types.str;
                default = "${cfg.home}/.config/sops/age/fido2/${config.securityKey.name}";
              };
              prfPath = mkOption {
                type = types.str;
                default = "${cfg.home}/.config/sops/age/prf/${config.securityKey.name}";
              };
            };

            sshKey = {
              public = mkOption {
                type = types.str;
                default =
                  if config.securityKey.name == "main" then
                    "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIKtQ/n+Lg+BZdaGKAkJNykyf93bjvr++lCnEeHQuV6oTAAAABHNzaDo= main-sk"
                  else
                    "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIGTDz1++tiT0SytsEP3XzTshTI6Edd+o6nMTVl/iLxzSAAAABHNzaDo= backup-sk";
              };
              privatePath = mkOption {
                type = types.str;
                default = "${cfg.home}/.ssh/${config.securityKey.name}_sk";
              };
            };

            syncthing = {
              id = mkNullOption "Syncthing Device ID";
              cert = mkNullOption "Syncthing Device certificate";
            };

            ip = mkNullOption "Local Network IP";
          };
        };
    in
    {
      options.me = {
        hosts = mkOption {
          description = "Central infrastructure definition";
          internal = true;
          type = types.attrsOf (types.submodule hostSubmodule);
          default = {
            mainKey.securityKey.name = "main";
            backupKey.securityKey.name = "backup";

            cray = {
              securityKey.name = "backup";
              syncthing = {
                id = "E5O7YJW-QG5GRP2-GTOIL44-GARB6IA-KVLTV4L-PNELNSW-U54NY7P-N3R5NQW";
                cert = "MIICHTCCAaOgAwIBAgIJAL9Q1/+3qvuJMAoGCCqGSM49BAMCMEoxEjAQBgNVBAoTCVN5bmN0aGluZzEgMB4GA1UECxMXQXV0b21hdGljYWxseSBHZW5lcmF0ZWQxEjAQBgNVBAMTCXN5bmN0aGluZzAeFw0yNDA3MTkwMDAwMDBaFw00NDA3MTQwMDAwMDBaMEoxEjAQBgNVBAoTCVN5bmN0aGluZzEgMB4GA1UECxMXQXV0b21hdGljYWxseSBHZW5lcmF0ZWQxEjAQBgNVBAMTCXN5bmN0aGluZzB2MBAGByqGSM49AgEGBSuBBAAiA2IABO2oK2ZKP3lp/PDySB7Sbsr4frvu9f4CB9tXoUXEThdCyxYmrwRuRtOic/l64G0UOEL9wDnNDqCb11HCGabDn/mxLtGMOYAWz8yy5CWOGTKTFzurM6gBqchJDNwpy9WLY6NVMFMwDgYDVR0PAQH/BAQDAgWgMB0GA1UdJQQWMBQGCCsGAQUFBwMBBggrBgEFBQcDAjAMBgNVHRMBAf8EAjAAMBQGA1UdEQQNMAuCCXN5bmN0aGluZzAKBggqhkjOPQQDAgNoADBlAjEAoZ3tD3CmeNqgfog1ksAlwrDtJG8afYxUqplmQoDjRRQOqJOCeMGqHX/BQwqrqdINAjAGmndmDmvLPMg97ZTByiZQbO+9Y0wQ98mAjaAn+2RfZQbPE2X2O+ZQkTMH2daJgOE=";
              };
              ip = "192.168.1.122";
            };

            woz = {
              syncthing = {
                id = "EE6ITAI-27EGPID-OCVK7I2-CMNOKJH-Y6M4GUY-RVP6WE2-PIV2OJ7-ISMCKAI";
                cert = "MIIBnzCCAVGgAwIBAgIIXyWhJFHxKeIwBQYDK2VwMEoxEjAQBgNVBAoTCVN5bmN0aGluZzEgMB4GA1UECxMXQXV0b21hdGljYWxseSBHZW5lcmF0ZWQxEjAQBgNVBAMTCXN5bmN0aGluZzAeFw0yNjA2MDkwMDAwMDBaFw00NjA2MDQwMDAwMDBaMEoxEjAQBgNVBAoTCVN5bmN0aGluZzEgMB4GA1UECxMXQXV0b21hdGljYWxseSBHZW5lcmF0ZWQxEjAQBgNVBAMTCXN5bmN0aGluZzAqMAUGAytlcAMhAIkLoEqrJ/y3+dAcX5UGmzN6u93iYg7QU3Uti/avHG82o1UwUzAOBgNVHQ8BAf8EBAMCBaAwHQYDVR0lBBYwFAYIKwYBBQUHAwEGCCsGAQUFBwMCMAwGA1UdEwEB/wQCMAAwFAYDVR0RBA0wC4IJc3luY3RoaW5nMAUGAytlcANBAHqXrnNUusIbdA4a9lbmpFOjs9FdjHnkbddjdR1Go39rRWeSOOZo9ejuKst86C99E5ZEemc+mIX5jUTDOgXLiAY=";
              };
              ip = "192.168.1.124";
            };

            cutler.syncthing.id = "XAFE3W3-FG4XVNB-GCPR4CU-XAYED7H-AISJHBI-JREWBFT-CLUTRPZ-EVYV5AH";

            julliard.sshKey.public = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOcGpmfziJoYbPbfdZi/REVStrNgl+F8lwVf1t2oLdaZ julliard";

            naitoh = {
              securityKey.name = "backup";
              syncthing = {
                id = "A4SN3P4-3UDLBHB-X3IG2A3-AZCXD5S-SQ6CTOY-SN3STI2-LVUGEP7-VT4X7A4";
                cert = "MIICHTCCAaOgAwIBAgIJAJ8i1BFHspdTMAoGCCqGSM49BAMCMEoxEjAQBgNVBAoTCVN5bmN0aGluZzEgMB4GA1UECxMXQXV0b21hdGljYWxseSBHZW5lcmF0ZWQxEjAQBgNVBAMTCXN5bmN0aGluZzAeFw0yNDA3MjAwMDAwMDBaFw00NDA3MTUwMDAwMDBaMEoxEjAQBgNVBAoTCVN5bmN0aGluZzEgMB4GA1UECxMXQXV0b21hdGljYWxseSBHZW5lcmF0ZWQxEjAQBgNVBAMTCXN5bmN0aGluZzB2MBAGByqGSM49AgEGBSuBBAAiA2IABOs1h24SG6BSQKrxPGwyl9hNIn0uF2BI60opj7jIP8Li0dPLusGyWfIodKlUskhqE4dc6bOuIdK/RVHmqEwt+cdHKWyUQRr4IZSvOZaEhfn2m1RgtzVcCeZEGeYL9rLwpaNVMFMwDgYDVR0PAQH/BAQDAgWgMB0GA1UdJQQWMBQGCCsGAQUFBwMBBggrBgEFBQcDAjAMBgNVHRMBAf8EAjAAMBQGA1UdEQQNMAuCCXN5bmN0aGluZzAKBggqhkjOPQQDAgNoADBlAjEA14v+C1RkCQteaf/BqYKd/X3Ut+iuCzeU2JPeV8y7B2fQpbc5wU6eJi7d721ZWCZaAjAZHQZRvoOv70/VdgjuTwjb6WRHiGCmiv0btujEjPjlLPkcuyXOCb+Nunyfj+BHLto=";
              };
              ip = "192.168.1.82";
            };

            mach = {
              syncthing = {
                id = "32SVOZP-RJL755K-D7ZTMRL-7FOTZZF-V7W5V5J-2JOIMCG-W6MRDGK-AO4D4AC";
                cert = "MIIBoDCCAVKgAwIBAgIJAPA5JeoDFWwfMAUGAytlcDBKMRIwEAYDVQQKEwlTeW5jdGhpbmcxIDAeBgNVBAsTF0F1dG9tYXRpY2FsbHkgR2VuZXJhdGVkMRIwEAYDVQQDEwlzeW5jdGhpbmcwHhcNMjYwMTEzMDAwMDAwWhcNNDYwMTA4MDAwMDAwWjBKMRIwEAYDVQQKEwlTeW5jdGhpbmcxIDAeBgNVBAsTF0F1dG9tYXRpY2FsbHkgR2VuZXJhdGVkMRIwEAYDVQQDEwlzeW5jdGhpbmcwKjAFBgMrZXADIQB4nrrv2Rlh6KN+QAuS/9buTkkT+IZtQ7m0Q3uPRoTUmqNVMFMwDgYDVR0PAQH/BAQDAgWgMB0GA1UdJQQWMBQGCCsGAQUFBwMBBggrBgEFBQcDAjAMBgNVHRMBAf8EAjAAMBQGA1UdEQQNMAuCCXN5bmN0aGluZzAFBgMrZXADQQCRPrVuQaWNo5UwYhnk2tTIK6vMgM7kcZXY77hGEOLjsXaQw1JhR+yQjpLk7vEKB1rbLNcnrPq3dVDjDC/RscMG";
              };
              sshKey.public = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBDIZOAfbe03pFpRXeB5ll3wNv+rZNgZg4rtCoiNELf3JJ7m54ze7QUrsy8LgIVk08r+Q8tuwA16yA+oDpK9fuys= mach";
              ip = "192.168.1.168";
            };

            geim.syncthing.id = "K3BCXJT-ZAFVPZV-RLJP4CM-NAOZGID-B44QXHR-5C7S3LD-RSEUPPO-YGH5ZAN";
            shannon.syncthing.id = "NCNYWXS-TGOZLXL-IZHMOQU-WNMNRSP-LDM5MFX-S4S5674-EYTMUAL-JB4WTQI";
            lamarr.syncthing.id = "ZMUWGAS-D7ETM4C-77LZJQD-T3VBPZS-UWXFTVN-K32GD5G-XKCP4UG-OMRG4AA";
            yoshino.syncthing.id = "4J5QS3L-TBUVQNM-RID2OP7-RTQG4GA-NWRB2E5-HXMTK7R-4C4QBFL-7M3RDAU";
          };
        };

        host = mkOption {
          type = types.submodule hostSubmodule;
          default = cfg.hosts.${cfg.hostname} or { };
          internal = true;
        };
      };
    };
}
