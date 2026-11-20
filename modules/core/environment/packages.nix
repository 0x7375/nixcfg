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
        mv.latest.codex
        dix
      ];
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
