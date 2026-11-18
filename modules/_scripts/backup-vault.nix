{ pkgs, ... }:
let
  server = "naitoh";
in
pkgs.writeShellApplication {
  name = "backup-vault";

  runtimeInputs = with pkgs; [
    zip
    openssh
    coreutils
    libfido2
    gawk
  ];

  text =
    # bash
    ''
      REMOTE_PATH=/data/main/backups/vault-export
      REMOTE="root@${server}"
      USAGE="Usage: backup-vault <export-file>... <usb-mount-path>"

      (( $# >= 2 )) || { echo "$USAGE"; exit 1; }

      USB_PATH="''${*: -1}"
      EXPORT_FILES=("''${@:1:$#-1}")

      [[ -d "$USB_PATH" ]] || {
        echo "USB path not found: $USB_PATH"
        exit 1
      }

      for f in "''${EXPORT_FILES[@]}"; do
        [[ -f "$f" ]] || {
          echo "File not found: $f"
          exit 1
        }
      done

      COUNT=$(fido2-token -L | awk 'NF {n++} END {print n+0}')
      if (( COUNT < 2 )); then
        echo "Two security keys must be connected."
        exit 1
      fi

      confirm() {
        local reply
        read -rn1 -p "$1 [Y/n] " reply || true
        echo
        [[ "''${reply:-Y}" =~ ^[Yy]$ ]]
      }

      TMP_DIR=$(mktemp -d)
      trap 'rm -rf -- "$TMP_DIR"' EXIT

      NAME="vault_$(date +%Y%m%d_%H%M%S).zip.age"
      ENCRYPTED="$TMP_DIR/$NAME"

      echo "Creating and encrypting archive..."

      if ! zip -q - "''${EXPORT_FILES[@]}" |
        fido2-encrypt > "$ENCRYPTED"; then
        echo "Encryption failed."
        exit 1
      fi

      [[ -s "$ENCRYPTED" ]] || {
        echo "Encrypted archive is empty."
        exit 1
      }

      copied=false
      failed=false

      if confirm "Copy to server?"; then
        if ssh "$REMOTE" -- mkdir -p "$REMOTE_PATH" \
          && scp "$ENCRYPTED" "$REMOTE:$REMOTE_PATH/$NAME"; then
          echo "* Copied to $REMOTE -> $REMOTE_PATH/$NAME"
          copied=true
        else
          failed=true
        fi
      fi

      if confirm "Copy to USB?"; then
        if cp "$ENCRYPTED" "$USB_PATH/$NAME" && sync; then
          echo "* Copied to USB -> $USB_PATH/$NAME"
          copied=true
        else
          failed=true
        fi
      fi

      if [[ "$copied" == true && "$failed" == false ]]; then
        if confirm "Delete originals?"; then
          for f in "''${EXPORT_FILES[@]}"; do
            shred -u -- "$f" && echo "* Deleted $f"
          done
        fi
      fi
    '';
}
