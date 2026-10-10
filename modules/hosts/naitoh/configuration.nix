{
  flake.modules.nixos.naitoh =
    {
      lib,
      config,
      ...
    }:
    {
      persist.directories = [
        "/data/main"
        "/var/lib/containers"
        "/var/lib/postgresql"
        "/var/lib/recyclarr"
      ];

      # automatically turn off display after 60s of inactivity
      boot.kernelParams = [ "consoleblank=60" ];

      users.users.${config.me.user}.openssh.authorizedKeys.keys = [
        config.me.hosts.mach.sshKey.public
      ];

      security.pam.services = lib.genAttrs [ "sudo" "su" "polkit-1" "login" ] (_: {
        unixAuth = lib.mkForce true;
      });

      services.journald.extraConfig = ''
        SystemMaxFileSize=40M
        SystemMaxUse=200M
      '';

      services.logind.settings.Login.HandleLidSwitch = "ignore";

      # do not change
      # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
      system.stateVersion = "23.11"; # Did you read the comment?
    };
}
