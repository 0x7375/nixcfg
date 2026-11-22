{ self, ... }:

{
  flake.modules.generic.core =
    {
      mv,
      inputs,
      pkgs,
      ...
    }:
    {
      packages = with pkgs; [
        wireguard-tools
        unzip
        (openssl.override { withZlib = true; })
        ncdu
        wget
        age
        bc
        ripgrep
        fd
        tlrc
        tree
        termdown
        caligula
        jq
        file

        nix-output-monitor
        inputs.nd.packages.${pkgs.stdenv.hostPlatform.system}.default
        inputs.npr.packages.${pkgs.stdenv.hostPlatform.system}.default
        my.nlink
        my.dump-dotfiles
        my.cuckcoding
        # wrapper to always trust current dir
        (pkgs.writeShellApplication {
          name = "codex";
          text = ''
            exec ${lib.getExe (self.lib.withMainProgram "codex" mv.latest.codex)} \
              -c "projects={\"$PWD\"={trust_level=\"trusted\"}}" \
              "$@"
          '';
        })
        dix
      ];

      hj.xdg.config.files."codex/config.toml" = {
        type = "copy";
        permissions = "0644";
        text = # toml
          ''
            check_for_update_on_startup = false
            sandbox_mode = "workspace-write"
          '';
      };
    };

  flake.modules.nixos.core =
    { pkgs, ... }:
    {
      persistUser.directories = [
        ".cache/tlrc"
        ".config/codex"
      ];

      packages = with pkgs; [
        efibootmgr
        gcc
      ];
    };
}
