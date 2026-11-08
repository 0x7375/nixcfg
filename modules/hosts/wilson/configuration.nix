{
  flake.modules.nixos.wilson =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    {
      me.uid = 1001;

      nixpkgs.overlays = lib.mkBefore [
        (final: prev: {
          crossPkgs = import prev.path {
            localSystem = "x86_64-linux";
            crossSystem = "aarch64-linux";
            config.allowUnfreePredicate = config.nixpkgs.config.allowUnfreePredicate;
          };
        })
      ];

      users.users.root.openssh.authorizedKeys.keys = config.me.hosts.mach.sshKey.public;

      security.pam.services = lib.genAttrs [ "sudo" "su" "polkit-1" "login" ] (_: {
        unixAuth = lib.mkForce true;
      });

      packages = with pkgs; [ ncdu ];

      services.journald.extraConfig = ''
        SystemMaxFileSize=40M
        SystemMaxUse=200M
      '';

      system.stateVersion = "24.11";
    };
}
