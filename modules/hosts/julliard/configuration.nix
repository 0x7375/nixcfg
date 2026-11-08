# NixOS-WSL specific options are documented on the NixOS-WSL repository:
# https://github.com/nix-community/NixOS-WSL
{
  flake.modules.nixos.julliard =
    {
      config,
      inputs,
      lib,
      pkgs,
      ...
    }:
    {
      imports = [ inputs.nixos-wsl.nixosModules.wsl ];

      me.user = "nixos";

      packages = with pkgs; [
        xclip
      ];

      wsl = {
        enable = true;
        defaultUser = config.me.user;
        wslConf.network.hostname = config.me.hostname;
        interop.register = true;
      };

      hj.xdg.config.files."lf/lfrc".text = ''
        map gh cd /mnt/c/Users/${config.me.user}
        map gm cd /mnt/c/Users/${config.me.user}/Documents
        map gw cd /mnt/c/Users/${config.me.user}/Downloads
        map gA cd /mnt/c/Users/${config.me.user}/AppData
        map gC cd /mnt/c/Users/${config.me.user}/.local/share/chezmoi
      '';

      nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";

      # This value determines the NixOS release from which the default
      # settings for stateful data, like file locations and database versions
      # on your system were taken. It's perfectly fine and recommended to leave
      # this value at the release version of the first install of this system.
      # Before changing this value read the documentation for this option
      # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
      system.stateVersion = "23.11"; # Did you read the comment?
    };
}
