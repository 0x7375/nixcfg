{ pkgs, ... }:
let
  server = "naitoh";
in
pkgs.writeShellApplication {
  name = "backup-vault";
  runtimeInputs = [ pkgs.rsync ];
  text =
    # bash
    ''
      REMOTE_PATH=/data/main/backups/vault-export
      REMOTE="root@${server}"
      USAGE="Usage: backup-vault <export-file>... <usb-mount-path>"

      (( $# >= 2 )) || { echo "$USAGE"; exit 1; }

      USB_PATH="''${*: -1}"
      EXPORT_FILES=("''${@:1:$#-1}")

      [[ -d "$USB_PATH" ]] || { echo "USB path not found: $USB_PATH"; exit 1; }
      for f in "''${EXPORT_FILES[@]}"; do
        [[ -f "$f" ]] || { echo "File not found: $f"; exit 1; }
      done

      confirm() {
        read -rn1 -p "$1 [Y/n] " REPLY
        echo
        [[ "''${REPLY:-Y}" =~ ^[Yy]$ ]]
      }

      stamp_name() {
        local f="$1" file base ext
        file="$(basename "$f")"
        base="''${file%%.*}"
        ext="''${file#*.}"
        echo "''${base}_$(date +%Y%m%d_%H%M%S).''${ext}"
      }

      if confirm "Copy to server?"; then
        ssh "$REMOTE" -- mkdir -p "$REMOTE_PATH"
        for f in "''${EXPORT_FILES[@]}"; do
          name="$(stamp_name "$f")"
          scp "$f" "$REMOTE:$REMOTE_PATH/$name" && \
          echo "* Copied to $REMOTE -> $REMOTE_PATH/$name"
        done
      fi

      if confirm "Copy to USB?"; then
        for f in "''${EXPORT_FILES[@]}"; do
          name="$(stamp_name "$f")"
          cp "$f" "$USB_PATH/$name" && \
          echo "* Copied to USB -> $USB_PATH/$name"
        done
        sync
      fi

      if confirm "Delete originals?"; then
        for f in "''${EXPORT_FILES[@]}"; do
          shred -u "$f" && echo "* Deleted $f"
        done
      fi
    '';
}
