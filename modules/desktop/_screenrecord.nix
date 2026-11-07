{ config, pkgs, ... }:
pkgs.writeShellApplication {
  name = "screenrecord";
  runtimeInputs = with pkgs; [
    coreutils
    xdg-user-dirs
    libnotify
    wf-recorder
    slurp
    wl-clipboard
    xdg-utils
    ffmpeg
    procps
  ];
  excludeShellChecks = [ "SC2012" ];
  bashOptions = [ ];
  text =
    let
      inherit (pkgs.lib) getExe;
      # TODO: make this shit better
      inherit (config.tinted.files.".config/mango/config.conf".value config.tinted.hex.dark) border_px;
    in
    # bash
    ''
      if pgrep -x "wf-recorder" >/dev/null; then
        filepath=$(ls -t "$(xdg-user-dir VIDEOS)"/* | head -1)

        pkill -INT -x wf-recorder
        sleep 1

        echo -n "file://$filepath" | wl-copy -t text/uri-list

        thumb="/tmp/thumb.png"
        ffmpeg -y -i "$filepath" -vframes 1 "$thumb" 2>/dev/null

        action=$(notify-send -i "$thumb" "Recording Saved" "$filepath" --action="delete=delete" --action="open=open")
        [[ "$action" == "open" ]] && xdg-open "$filepath"
        [[ "$action" == "delete" ]] && rm "$filepath"
        rm -f "$thumb"

        exit 0
      fi

      usage() {
        echo "Usage: screenrecord {area|monitor}"
        exit 1
      }

      [[ -z "$1" ]] && usage

      audio_list=$(wpctl status | awk '/\[vol:/ { sub(/.*│[ *]*/, ""); sub(/ *\[vol:.*/, ""); sub(/\. /, " "); print }')
      no_audio="No audio"
      audio_choice=$(printf "$no_audio\n%s" "$audio_list" | ${getExe pkgs.noctalia} dmenu -p "Audio to capture...")
      [[ -z "$audio_choice" ]] && exit 0

      audio_flag=""
      if [[ "$audio_choice" != "$no_audio" ]]; then
        audio_id=$(echo "$audio_choice" | awk '{print $1}')
        audio_flag="--audio-backend=pipewire -a $audio_id"
      fi

      time=$(date -u "+%s" | cut -c 7-)
      file="Record-$(date -u +%d-%m-%Y-"$time").mp4"
      folder="$(xdg-user-dir VIDEOS)/"
      filepath="$folder$file"

      color_opts="-p color_primaries=bt709 -p color_trc=bt709 -p colorspace=bt709"

      if [[ -c "/dev/nvidia0" ]]; then
        enc_opts="$audio_flag -c h264_nvenc -p preset=p7 -p tune=hq -p rc=constqp -p qp=18 $color_opts"
      else
        enc_opts="$audio_flag -c libx264 -p preset=superfast -p crf=18 $color_opts"
      fi

      # yuv420p requires even dimensions
      filter="scale=out_color_matrix=bt709,format=yuv420p,pad=ceil(iw/2)*2:ceil(ih/2)*2"

      case "$1" in
        area)
          clients=$(mmsg get all-clients | jq -r '.clients[] | select(.is_visible) | (if .is_fullscreen then 0 else ${toString border_px} end) as $b | "\(.x + $b),\(.y + $b) \(.width - 2*$b)x\(.height - 2*$b)"')
          selection=$(echo "$clients" | slurp -f "%o %x,%y %wx%h")
          [[ -z "$selection" ]] && exit 1

          read -r mon geom <<< "$selection"
          IFS=' x' read -r _ w h <<< "$geom"

          # fallback to software encoding (fails with hw enc)
          if (( w < 160 || h < 160 )); then
            enc_opts="$audio_flag -c libx264 -p preset=superfast -p crf=18"
          fi

          record_cmd="wf-recorder -o \"$mon\" -g \"$geom\" -F \"$filter\" -f \"$filepath\" $enc_opts"
          ;;
        monitor)
          active_mon=$(mmsg get focusing-client | jq .monitor)
          record_cmd="wf-recorder -o \"$active_mon\" -F \"$filter\" -f \"$filepath\" $enc_opts"
          ;;
        *)
          usage
          ;;
      esac

      ${getExe pkgs.my.notify} -i video "Recording Started" "Mode: $1" -t 2000

      eval "$record_cmd"
    '';
}
