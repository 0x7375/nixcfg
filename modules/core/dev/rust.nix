{
  flake.modules.nixos.dev =
    { pkgs, mv, ... }:
    {
      packages =
        with pkgs;
        let
          at = mv.at "2026-06-01";
        in
        [
          bacon
          at.rustc
          at.cargo
          at.clippy
          at.clang
          at.mold
          (pkgs.rustPlatform.buildRustPackage (
            let
              src = pkgs.fetchFromGitHub {
                owner = "0x7375";
                repo = "maudfmt";
                rev = "c9fb0cf82c57686e62bf627d8dbaabd7c8fd70e1";
                hash = "sha256-67PiX92voaew8/JlzxfyiBRaO7982A263gG7B2ywnl8=";
              };
            in
            {
              pname = "maudfmt";
              version = "unstable-2026-08-24";
              inherit src;
              cargoLock = {
                lockFile = "${src}/Cargo.lock";
                outputHashes = {
                  "prettyplease-0.2.37" = "sha256-fnhSiVKs/uhOJMNEnKj20z6Dm3bSz2k7mFThYtba/GE=";
                };
              };

              doCheck = false;
            }
          ))

        ];

      hj.xdg.data.files."cargo/config.toml".text = # toml
        ''
          [target.aarch64-unknown-linux-gnu]
          linker = "clang"
          rustflags = ["-C", "link-arg=-fuse-ld=mold"]
        '';

      hj.xdg.config.files."bacon/prefs.toml".text = # toml
        ''
          help_line = false
          hide_scrollbar = true
          [keybindings]
          g = "scroll-to-top"
          shift-g = "scroll-to-bottom"
          k = "scroll-lines(-1)"
          j = "scroll-lines(1)"
          ctrl-u = "scroll-page(-1)"
          ctrl-d = "scroll-page(1)"

          [skin]
          status_fg = 0
          status_bg = 7

          project_name_badge_fg = 0
          project_name_badge_bg = 7

          job_label_badge_fg = 0
          job_label_badge_bg = 6

          computing_fg = 0
          computing_bg = 6

          status_key_fg = 0
          command_error_badge_fg = 0
          errors_badge_fg = 0
          warnings_badge_fg = 0
        '';
    };
}
