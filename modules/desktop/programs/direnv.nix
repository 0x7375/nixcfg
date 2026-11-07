{
  flake.modules.generic.desktop =
    {
      pkgs,
      lib,
      ...
    }:
    {

      vars.DIRENV_WARN_TIMEOUT = "0";

      aliases.direnvrc = "echo 'use_flake' > .envrc && direnv allow";

      hj.xdg.config.files."zsh/.zshrc".text =
        lib.mkAfter "command -v direnv &> /dev/null && eval \"$(direnv hook zsh)\"";

      hj.files.".bashrc".text =
        lib.mkAfter "command -v direnv &> /dev/null && eval \"$(direnv hook bash)\"";

      packages = with pkgs; [
        direnv
      ];

      hj.xdg.config.files."direnv/direnv.toml" = {
        generator = (pkgs.formats.toml { }).generate "direnv.toml";
        value.global = {
          log_format = "-";
          log_filter = "^$";
        };
      };

      hj.xdg.config.files."direnv/lib/nix-direnv.sh".source =
        "${pkgs.nix-direnv}/share/nix-direnv/direnvrc";

      hj.xdg.config.files."direnv/direnvrc".text =
        # bash
        ''
          : "''${XDG_CACHE_HOME:="''${HOME}/.cache"}"
          declare -A direnv_layout_dirs
          direnv_layout_dir() {
              local hash path
              echo "''${direnv_layout_dirs[$PWD]:=$(
                  hash="''$(sha1sum - <<< "$PWD" | head -c40)"
                  path="''${PWD//[^a-zA-Z0-9]/-}"
                  echo "''${XDG_CACHE_HOME}/direnv/layouts/''${hash}''${path}"
              )}"
          }

          export DIRENV_LOADED=1
        '';
    };

  flake.modules.nixos.desktop =
    { pkgs, ... }:
    {
      persistUser.directories = [
        ".cache/direnv"
        ".local/share/direnv"
      ];

      packages = [ pkgs.devenv ];
    };
}
