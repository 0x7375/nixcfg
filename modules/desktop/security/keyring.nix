{
  flake.modules.nixos.desktop =
    {
      pkgs,
      lib,
      ...
    }:
    {
      nixpkgs.overlays = [
        (final: prev: {
          pass-secret-service-rs = prev.callPackage ./_pass-secret-service-rs.nix { };
        })
      ];

      persistUser.directories = [
        {
          directory = ".gnupg";
          mode = "0700";
        }
        {
          directory = ".password-store";
          mode = "0700";
        }
      ];

      services.passSecretService = {
        enable = true;
        package = pkgs.pass-secret-service-rs;
      };

      packages = with pkgs; [
        pass
        gnupg
        seahorse
      ];

      userActivation =
        # bash
        ''
          set -euo pipefail

          export GNUPGHOME="$HOME/.gnupg"
          export PASSWORD_STORE_DIR="$HOME/.password-store"

          GPG="${lib.getExe pkgs.gnupg}"
          PASS="${lib.getExe pkgs.pass}"
          AWK="${lib.getExe pkgs.gawk}"
          RECIPIENT="secrets@localhost"

          mkdir -p "$GNUPGHOME" "$PASSWORD_STORE_DIR"
          chmod 700 "$GNUPGHOME" "$PASSWORD_STORE_DIR"

          # Create an unprotected key if it doesn't exist.
          if ! "$GPG" --list-secret-keys "$RECIPIENT" &>/dev/null; then
            "$GPG" --batch --gen-key <<EOF
          %no-protection
          Key-Type: EdDSA
          Key-Curve: ed25519
          Subkey-Type: ECDH
          Subkey-Curve: cv25519
          Name-Real: Secrets
          Name-Email: secrets@localhost
          Expire-Date: 0
          %commit
          EOF
          fi

          # Retrieve the primary key fingerprint.
          KEY_FINGERPRINT="$("$GPG" --with-colons --list-secret-keys "$RECIPIENT" |
            "$AWK" -F: '$1 == "fpr" { print $10; exit }')"

          if [ -z "$KEY_FINGERPRINT" ]; then
            echo "Failed to retrieve GPG key fingerprint." >&2
            exit 1
          fi

          # Ensure an encryption-capable secret subkey exists.
          if ! "$GPG" --with-colons --list-secret-keys "$KEY_FINGERPRINT" |
            "$AWK" -F: '$1 == "ssb" && $12 ~ /e/ { found = 1 } END { exit !found }'
          then
            echo "Adding missing encryption subkey..."

            "$GPG" --batch \
              --pinentry-mode loopback \
              --passphrase "" \
              --quick-add-key "$KEY_FINGERPRINT" cv25519 encr never
          fi

          # Initialize the password store if necessary.
          if [ ! -f "$PASSWORD_STORE_DIR/.gpg-id" ]; then
            "$PASS" init "$RECIPIENT"
          fi
        '';
    };
}
