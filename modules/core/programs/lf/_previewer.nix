{
  isLinux,
  pkgs,
  ...
}:

pkgs.writeShellApplication {
  name = "previewer";
  runtimeInputs =
    with pkgs;
    [
      bat
      file
      w3m
      delta
      chafa
      imagemagick
      ffmpegthumbnailer
      poppler-utils
      fontforge
    ]
    ++ pkgs.lib.optionals isLinux (
      with pkgs;
      [
        libreoffice
      ]
    );
  text = ''
    chafa_preview() {
      chafa --format sixels --size "''${width}x''${height}" "$1"
    }

    preview_cached() {
      if ! [ -f "$cache" ]; then
        dir="$(dirname -- "$cache")"
        [ -d "$dir" ] || mkdir -p -- "$dir"
        "$@"
      fi
      chafa_preview "$cache"
    }

    hash() {
      cache="$HOME/.cache/lf/$(stat --printf '%n\0%i\0%F\0%s\0%W\0%Y' -- "$(readlink -f -- "$1")" | sha256sum | cut -d' ' -f1).jpg"
    }

    file="$1"
    width="$2"
    height="$3"

    case "''${file##*.}" in
      pem | env | gpg | keyring)
        echo "preview disabled"
        exit 0
        ;;
    esac

    hash "$file"
    case "$(file -Lb --mime-type -- "$file")" in
      image/svg+xml)
        preview_cached convert "$file" "$cache"
        ;;
      image/*)
        orientation="$(magick identify -format '%[orientation]\n' -- "$file")"
        if [ -n "$orientation" ] \
          && [ "$orientation" != Undefined ] \
          && [ "$orientation" != TopLeft ]; then
          preview_cached magick -- "$file" -auto-orient "$cache"
        else
          chafa_preview "$file"
        fi
        ;;
      video/*)
        preview_cached ffmpegthumbnailer -i "$file" -o "$cache" -s 0
        ;;

      audio/*)
        ffmpeg -hide_banner -i "$file" 2>&1 | grep -v "^ffmpeg\|^Input\|At least"
        ;;

      application/zip | \
        application/x-tar | \
        application/x-7z-compressed | \
        application/gzip | \
        application/x-bzip2 | \
        application/x-xz | \
        application/x-rar)
        atool -l "$file"
        ;;

      font/* | \
        application/font* | \
        application/x-font*)
        preview_cached fontimage -o "$cache" "$file"
        ;;

      application/pdf)
        preview_cached pdftoppm -jpeg -f 1 -singlefile "$file" "''${cache%.jpg}"
        ;;

      application/vnd.openxmlformats-officedocument.* | \
        application/vnd.ms-* | \
        application/msword | \
        application/vnd.oasis.*)
        # shellcheck disable=SC2329
        office_to_jpg() {
          tmp="$(mktemp -d)"
          libreoffice --headless --convert-to pdf --outdir "$tmp" "$file" 2>/dev/null
          pdftoppm -jpeg -f 1 -singlefile "$tmp"/*.pdf "''${cache%.jpg}"
          rm -rf "$tmp"
        }
        preview_cached office_to_jpg
        ;;

      text/x-diff | \
        text/x-patch)
        delta < "$file"
        ;;

      text/html)
        w3m "$file"
        ;;
      *)
        if file -L --mime-encoding -- "$file" | grep -q "binary"; then
          file -Lb "$file"
        else
          bat --color=always --style=plain "$file" || echo "oopsie"
        fi
        ;;
    esac

    exit 0
  '';
}
