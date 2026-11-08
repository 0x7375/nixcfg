{
  flake.modules.nixos.pearlman =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    {
      me.tpm.enable = true;

      services.logind.settings.Login.HandleLidSwitch = "ignore";
      powerManagement.cpuFreqGovernor = "performance";

      hardware.graphics = {
        enable = true;
        extraPackages = with pkgs; [
          intel-media-driver
          intel-vaapi-driver
        ];
      };

      users.users.root.openssh.authorizedKeys.keys = config.me.hosts.mach.sshKey.public;

      security.pam.services = lib.genAttrs [ "sudo" "su" "polkit-1" "login" ] (_: {
        unixAuth = lib.mkForce true;
      });

      systemd.services.blank-tty = {
        wantedBy = [ "multi-user.target" ];
        after = [ "getty.target" ];
        serviceConfig = {
          Type = "oneshot";
          Environment = "TERM=linux";
          StandardOutput = "tty";
          TTYPath = "/dev/tty1";
          ExecStart = "${lib.getExe' pkgs.util-linux "setterm"} --blank 1 --powerdown 2";
        };
      };

      # because bios settings are unreliable
      services.timesyncd.servers = [
        "162.159.200.1" # Cloudflare NTP
        "216.239.35.0" # Google NTP
      ];

      boot.tmp.tmpfsSize = "512M";

      virtualisation.containers.storage.settings.storage = {
        driver = "overlay";
        graphroot = "/mnt/ssd/containers/storage";
        runroot = "/run/containers/storage";
      };

      packages = with pkgs; [ ncdu ];

      services.journald.extraConfig = ''
        SystemMaxFileSize=40M
        SystemMaxUse=200M
      '';

      system.stateVersion = "25.11";
    };
}
