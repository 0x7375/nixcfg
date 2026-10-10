{
  self,
  inputs,
  ...
}:

let
  inherit (inputs.nixpkgs) lib;
  # for each module name: both generic+platform if both exist, otherwise whichever does
  mkScope =
    generic: platform:
    lib.genAttrs (lib.attrNames (generic // platform)) (
      name:
      if generic ? ${name} && platform ? ${name} then
        {
          imports = [
            generic.${name}
            platform.${name}
          ];
        }
      else
        generic.${name} or platform.${name}
    );

  scope = {
    nixos = mkScope self.modules.generic self.modules.nixos;
    darwin = mkScope self.modules.generic self.modules.darwin;
  };

  mkHost =
    type: name: extraModules:
    let
      isNixos = type == "nixos";
      mkSystem = if isNixos then lib.nixosSystem else inputs.nix-darwin.lib.darwinSystem;
      mod = if isNixos then "nixosModules" else "darwinModules";
      modName = if isNixos then "nixos" else "darwin";
    in
    mkSystem {
      inherit lib;
      specialArgs = {
        inherit inputs;
        secrets = ../secrets;
      };
      modules = [
        inputs.sops-nix.${mod}.sops
        inputs.nix-index-database.${mod}.nix-index
        inputs.hjem.${mod}.default
        inputs.nixcord.${mod}.nixcord

        self.modules.${modName}.${name}
        scope.${modName}.core
        scope.${modName}.custom
        { networking.hostName = name; }
      ]
      ++ lib.optionals isNixos [
        inputs.disko.nixosModules.disko
        inputs.preservation.nixosModules.default
        inputs.nixflix.nixosModules.default
        self.modules.nixos.overrides
      ]
      ++ extraModules;
    };
in
{
  # allow it to be merged
  options.flake.lib = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.raw;
    default = { };
  };

  config = {
    flake.nixosConfigurations = {
      cray = mkHost "nixos" "cray" (
        with scope.nixos;
        [
          boot
          secrets
          networkEnvironment
          keyd
          btrfs
          homeVpnClient
          syncthingClient
          desktop
          wayland
          dev
          docker
          kitty
          preservation
        ]
      );

      naitoh = mkHost "nixos" "naitoh" (
        with scope.nixos;
        [
          boot
          secrets
          network
          keyd
          btrfs
          syncthing
          docker
          preservation
        ]
      );

      woz = mkHost "nixos" "woz" (
        with scope.nixos;
        [
          keyd
          laptop
          boot
          secrets
          networkEnvironment
          btrfs
          syncthingClient
          homeVpnClient
          desktop
          docker
          wayland
          dev
          preservation
          kitty
        ]
      );

      # pearlman = mkHost "nixos" "pearlman" (
      #   with scope.nixos;
      #   [
      #     boot
      #     secrets
      #     syncthing
      #     network
      #   ]
      # );

      isoImg = mkHost "nixos" "isoImg" (
        with scope.nixos;
        [
          keyd
        ]
      );
    };

    flake.darwinConfigurations = {
      mach = mkHost "darwin" "mach" (
        [
          inputs.nix-homebrew.darwinModules.nix-homebrew
        ]
        ++ (with scope.darwin; [
          secrets
          homeVpnClient
          desktop
          kitty
          network
          dev
        ])
      );
    };
  };
}
