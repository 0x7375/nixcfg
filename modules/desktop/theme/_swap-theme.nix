{
  config,
  pkgs,
  ...
}:

let
  inherit (pkgs.stdenv) isDarwin;
  inherit (pkgs) lib;
in
pkgs.writeShellApplication {
  name = "swap-theme";
  bashOptions = [ "nounset" ];
  excludeShellChecks = [
    "SC2034"
    "SC2154"
    "SC1091"
  ];
  runtimeInputs =
    with pkgs;
    [
      procps
      fd
    ]
    ++ lib.optionals (!isDarwin) (
      with pkgs;
      [
        dconf
        dunst
        swaybg
        mango
        noctalia
      ]
    );
  text =
    # bash
    ''
      themes_dir="$TINTED_DIR"
      share_dir="$HOME/.local/share"
      theme_file="''${themes_dir}/theme"

      # default to dark
      [[ -f "$theme_file" ]] || echo "dark" > "$theme_file"

      theme=light
      theme_bool=false

      current_theme=$(< "$theme_file")

      case ''${1:-} in
        sync)
          theme="$current_theme"
          if command -v noctalia >/dev/null; then
            theme=$(noctalia msg theme-mode-get || echo "$current_theme")
          else
            defaults read -g AppleInterfaceStyle &>/dev/null && theme=dark
          fi
          ;;
        light|dark)
          theme=$1
          ;;
        *)
          [[ $current_theme == light ]] && theme=dark || theme=light
          ;;
      esac

      echo "$theme" > "$theme_file"
      [[ "$theme" == "dark" ]] && theme_bool="true"

      fd --hidden ".*-dark" "$themes_dir" | while read -r dark_file; do
        base_path="''${dark_file%-dark}"
        config_path="''${base_path#"$themes_dir"/}"
        mkdir -p "$(dirname "$HOME/$config_path")"
        ln -sf "''${base_path}-''${theme}" "$HOME/$config_path"
      done

      (
        export XDG_CACHE_HOME="$HOME/.cache"
        cd "${pkgs.emptyDirectory}" || exit
        ${lib.getExe pkgs.bat} cache --build > /dev/null 2>&1
      )

      ${
        if !isDarwin then
          let
            inherit (config.me.desktop) theme iconTheme;
          in
          # bash
          ''
            mkdir -p "$share_dir/icons" "$share_dir/themes"
            ln -sfT "${theme.package}/share/themes/${theme.name}-''${theme^}" "$share_dir/themes/${theme.name}"
            ln -sfT "${iconTheme.package}/share/icons/${iconTheme.name}-''${theme^}" "$share_dir/icons/${iconTheme.name}"

            dconf write /org/gnome/desktop/interface/color-scheme "'prefer-$theme'"

            wallpaper=$(shuf -e -n1 --random-source=<(date +%Y%m%d | md5sum) ~/pictures/wallpapers/"$theme"/*)
            noctalia msg wallpaper-set "$wallpaper"

            mmsg dispatch reload_config 

            if [[ "$theme" == "dark" ]]; then
              pkill -USR1 foot
            else
              pkill -USR2 foot
            fi
          ''
        else
          # bash
          ''
            [[ ''${1:-} != "sync" ]] &&  osascript -e "tell app \"System Events\" to tell appearance preferences to set dark mode to ''${theme_bool}"
          ''
      }
      pkill -USR1 nvim
    '';
}
