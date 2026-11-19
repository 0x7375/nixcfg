{
  flake.modules.darwin.dev = { pkgs, ... }: {
    packages = with pkgs; [
      # karabiner
      nodejs_24
    ];
  };

  flake.modules.generic.dev =
    { pkgs, ... }:
    {
      packages = with pkgs; [ gnumake ];

      hj.xdg.config.files."clangd/config.yaml".text = # yaml
        ''
          CompileFlags:
            BuiltinHeaders: QueryDriver
        '';
    };

  flake.modules.nixos.dev =
    { pkgs, ... }:
    {
      persistUser.directories = [
        "Android"
        ".config/Google"
        ".local/share/gradle"
        ".cache/Google"
      ];

      packages = with pkgs; [
        go
        delve

        # nodePackages.eas-cli
        # nodejs_24
        # deno

        # haskell
        # ghc

        php
        # nodePackages.intelephense

        # java
        zulu

        # c
        clang-tools
        gcc
        bear
        gdb

        tailwindcss_4

        python3
        taplo
      ];
    };
}
