{
  flake.modules.nixos.core =
    {
      config,
      ...
    }:
    {
      systemd.tmpfiles.settings.cleanup =
        let
          dir = {
            mode = "0755";
            inherit (config.me) user;
            group = "users";
          };
        in
        {
          "${config.me.home}/.local".d = dir;
          "${config.me.home}/.local/share".d = dir;
          "${config.me.home}/.local/share/android".d = dir;
          "${config.me.home}/.local/share/gnupg".d = {
            mode = "0700";
            inherit (config.me) user;
            group = "users";
          };
        };

      vars = rec {
        XDG_RUNTIME_DIR = "/run/user/$UID";
        XAUTHORITY = "${XDG_RUNTIME_DIR}/Xauthority";
        NPM_CONFIG_TMP = "${XDG_RUNTIME_DIR}/npm";
      };
    };

  flake.modules.generic.core =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      inherit (lib) getExe' getExe;
    in
    {
      vars = rec {
        XDG_DATA_HOME = "$HOME/.local/share";
        XDG_STATE_HOME = "$HOME/.local/state";
        XDG_BIN_HOME = "$HOME/.local/bin";
        XDG_CONFIG_HOME = "$HOME/.config";
        XDG_CACHE_HOME = "$HOME/.cache";
        PATH = [ "${XDG_BIN_HOME}" ];
        RANDFILE = "${XDG_STATE_HOME}/rnd";
        HISTFILE = "${XDG_STATE_HOME}/bash/history";
        PYTHON_HISTORY = "${XDG_STATE_HOME}/python_history";
        GOPATH = "${XDG_DATA_HOME}/go";
        PGPASSFILE = "${XDG_CONFIG_HOME}/pg/pgpass";
        MYSQL_HISTFILE = "${XDG_DATA_HOME}/mysql_history";
        PSQL_HISTORY = "${XDG_DATA_HOME}/psql_history";
        _Z_DATA = "${XDG_DATA_HOME}/z";
        ANSIBLE_HOME = "${XDG_DATA_HOME}/ansible";
        CARGO_HOME = "${XDG_DATA_HOME}/cargo";
        CUDA_CACHE_PATH = "${XDG_CACHE_HOME}/nv";
        GRADLE_USER_HOME = "${XDG_DATA_HOME}/gradle";
        NIMBLE_DIR = "${XDG_DATA_HOME}/nimble";
        STACK_ROOT = "${XDG_DATA_HOME}/stack";
        TEXMFVAR = "${XDG_CACHE_HOME}/texlive/texmf-var";
        WINEPREFIX = "${XDG_DATA_HOME}/wine";
        CABAL_DIR = "${XDG_DATA_HOME}/cabel";
        CABAL_CONFIG = "${XDG_CONFIG_HOME}/cabal/config";
        ZDOTDIR = "${XDG_CONFIG_HOME}/zsh";
        NPM_CONFIG_USERCONFIG = "${XDG_CONFIG_HOME}/npm/npmrc";
        NPM_CONFIG_INIT_MODULE = "${XDG_CONFIG_HOME}/npm/config/npm-init.js";
        NPM_CONFIG_CACHE = "${XDG_CACHE_HOME}/npm";
        RUSTUP_HOME = "${XDG_DATA_HOME}/rustup";
        ERRFILE = "${XDG_CACHE_HOME}/X11/xsession-errors";
        ANDROID_USER_HOME = "${XDG_DATA_HOME}/android";
        W3M_DIR = "${XDG_CONFIG_HOME}/w3m";
      };

      aliases = {
        nvidia-settings = "nvidia-settings --config=${config.vars.XDG_CONFIG_HOME}/nvidia/settings";
        svn = "${getExe' pkgs.subversion "svn"} --config-dir $XDG_CONFIG_HOME/subversion";
        adb = "HOME=${config.vars.XDG_DATA_HOME}/android ${getExe' pkgs.android-tools "adb"}";
        wget = "${getExe pkgs.wget} --hsts-file=$XDG_DATA_HOME/wget-hsts";
      };

      hj.xdg.config.files."vim/vimrc".text = # vim
        ''
          set viminfo+=n~/.local/state/viminfo
        '';

      hj.xdg.config.files."npm/npmrc".text = ''
        prefix=''${XDG_DATA_HOME}/npm
        cache=''${XDG_CACHE_HOME}/npm
        init-module=''${XDG_CONFIG_HOME}/npm/config/npm-init.js
        tmp=''${XDG_RUNTIME_DIR}/npm
      '';
    };
}
