{
  flake.modules.nixos.cray = { config, lib, ... }: {
    systemd.coredump.enable = lib.mkForce true;
    boot.supportedFilesystems = [ "ntfs" ];

    # boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

    vars = {
      LIBVA_DRIVER_NAME = "nvidia";
      GBM_BACKEND = "nvidia-drm";
      __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    };

    services.xserver.videoDrivers = [ "nvidia" ];
    unfree-packages = [
      "nvidia-x11"
      "nvidia-settings"
    ];

    nix.settings = {
      cores = 5;
      max-jobs = 4;
    };

    users.users.${config.me.user}.openssh.authorizedKeys.keys = [
      # woz ssh key to use this machine as a builder for kernel stuff
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIODU2bMHmJQugnGaQQzfeuEsc0BN1p1C4M9nCoxJw0nu root@woz"
    ];

    tinted.files.".config/mango/config.conf".value.mouse_accel_profile = "1";

    time.hardwareClockInLocalTime = true;

    tinted.files.".config/mango/config.conf".value.exec-once = [
      "mmsg dispatch viewcrossmon,5,HDMI-A-1 && mmsg dispatch viewcrossmon,1,HDMI-A-2"
    ];

    # do not change
    # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
    system.stateVersion = "23.11"; # Did you read the comment?
  };
}
