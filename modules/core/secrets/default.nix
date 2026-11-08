{
  flake.modules.generic.secrets =
    {
      pkgs,
      secrets,
      config,
      mv,
      lib,
      ...
    }:
    {
      options.me.hostSecrets = lib.mkOption {
        type = lib.types.attrsOf lib.types.attrs;
        default = { };
        example = lib.literalExpression ''{ "secret/path" = { owner = "bla"; }; }'';
        description = "Secrets that automatically map to the host's sops default.yaml";
      };

      config = {
        sops.secrets = lib.mapAttrs (
          name: extra:
          {
            sopsFile = "${secrets}/${config.me.hostname}/default.yaml";
            key = name;
          }
          // extra
        ) config.me.hostSecrets;

        nixpkgs.overlays = [
          (final: prev: {
            mv-age-plugin-tpm = mv.version "age-plugin-tpm" "1.0.1";
          })
        ];

        packages = with pkgs; [
          sops
          age-plugin-fido2-hmac
          mv-age-plugin-tpm
        ];

        sops.defaultSopsFile = "${secrets}/default.yaml";
        sops.gnupg.sshKeyPaths = [ ];
        sops.age.sshKeyPaths = [ ];
        sops.age.plugins = [ pkgs.age-plugin-fido2-hmac ];

        hj.xdg.config.files =
          let
            mkKeyConfig = path: {
              text = builtins.readFile path;
              type = "copy";
              permissions = "0600";
            };
          in
          {
            "sops/age/fido2/backup" = mkKeyConfig ./keys/fido2/backup;
            "sops/age/fido2/main" = mkKeyConfig ./keys/fido2/main;
            "sops/age/prf/main" = mkKeyConfig ./keys/prf/main;
            "sops/age/prf/backup" = mkKeyConfig ./keys/prf/backup;
          };

        vars.SOPS_AGE_KEY_FILE = config.me.host.securityKey.fido2Path;
      };
    };

  flake.modules.generic.desktop =
    { pkgs, ... }:
    {
      packages = [ pkgs.age-plugin-se ];
    };

  flake.modules.nixos.secrets =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      persistDir = if config.preservation.enable then "/persist" else "";
    in
    {
      options.me.tpm.enable = lib.mkEnableOption "Setup tpm and decrypt sops-nix secrets using tpm";

      config = lib.mkMerge [
        (lib.mkIf config.me.tpm.enable {
          persist.files = [ "/etc/tpm_key" ];

          sops.age = {
            keyFile = "${persistDir}/etc/tpm_key";
            plugins = [ pkgs.mv-age-plugin-tpm ];
          };

          packages = with pkgs; [ tpm2-tools ];

          security.tpm2 = {
            enable = true;
            pkcs11.enable = true;
            tctiEnvironment.enable = true;
          };
        })
        (lib.mkIf (!config.me.tpm.enable) {
          sops.age.sshKeyPaths = [ "${persistDir}/etc/ssh/ssh_host_ed25519_key" ];
        })
      ];
    };

  flake.modules.darwin.secrets =
    { pkgs, ... }:
    {
      sops.age = {
        keyFile = "/var/lib/sops-nix/se-identity.txt";
        plugins = with pkgs; [
          # sometimes needed I don't get it
          (pkgs.runCommand "sops-darwin-paths" { } ''
            mkdir -p $out/bin
            ln -s /usr/bin/hdiutil $out/bin/hdiutil
            ln -s /usr/bin/getconf $out/bin/getconf
            ln -s /sbin/newfs_hfs $out/bin/newfs_hfs
            ln -s /sbin/mount $out/bin/mount
          '')
          age-plugin-se
        ];
      };
    };
}
