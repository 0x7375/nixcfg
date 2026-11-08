{
  flake.modules.nixos.naitoh =
    {
      pkgs,
      config,
      ...
    }:
    {
      hardware.graphics.enable = true;

      nixpkgs.overlays = [
        (final: prev: {
          # kdePackages = prev.unstable.kdePackages;
        })
      ];

      unfree-packages = [ "mdk-sdk" ];

      services.desktopManager.plasma6.enable = true;
      packages = with pkgs; [
        kdePackages.plasma-bigscreen
        jellyfin-desktop
        fladder
      ];
      programs.kdeconnect.enable = true;

      services.getty.autologinUser = null;

      services.greetd = {
        enable = true;
        settings = {
          initial_session = {
            command = "plasma-bigscreen-wayland";
            inherit (config.me) user;
          };
          default_session = {
            command = "plasma-bigscreen-wayland";
            inherit (config.me) user;
          };
        };
      };
    };
}
