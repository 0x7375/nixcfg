{ config, pkgs, ... }:
pkgs.writeShellApplication {
  name = "screenshot";
  runtimeInputs = with pkgs; [
    coreutils
    xdg-user-dirs
    libnotify
    grim
    slurp
    wl-clipboard
    xdg-utils
  ];
  text =
    let
      inherit (config.tinted.files.".config/mango/config.conf".static) border_px;
    in
    # bash
    ''
      time=$(date -u "+%s" | cut -c 7-)
      file="Screenshot-$(date -u +%d-%m-%Y-"$time").png"
      folder="$(xdg-user-dir SCREENSHOTS)/"
      filepath="$folder$file"

      usage() {
        echo "Usage: screenshot {area|monitor}"
        exit 1
      }

      [[ -z "$1" ]] && usage

      active_mon=$(mmsg get focusing-client | jq .monitor)

      case "$1" in
        area)
          clients=$(mmsg get all-clients | jq -r '.clients[] | select(.is_visible) | (if .is_fullscreen then 0 else ${toString border_px} end) as $b | "\(.x + $b),\(.y + $b) \(.width - 2*$b)x\(.height - 2*$b)"')
          geom=$(echo "$clients" | slurp -b '#00000099' -B '#00000060')
          [[ -z "$geom" ]] && exit 1
          
          grim -g "$geom" "$filepath"
          ;;
        monitor)
          active_mon=$(mmsg get focusing-client | jq -r .monitor)
          grim -o "$active_mon" "$filepath"
          ;;
        *)
          usage
          ;;
      esac

      wl-copy < "$filepath"

      (
       action=$(notify-send -i "$filepath" "Screenshot saved" "$filepath" --action="delete=delete" --action="open=open")
       [[ "$action" == "open" ]] && xdg-open "$filepath"
       [[ "$action" == "delete" ]] && rm "$filepath"
      ) &
    '';
}
