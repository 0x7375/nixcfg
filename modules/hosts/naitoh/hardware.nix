{
  flake.modules.nixos.naitoh =
    {
      config,
      lib,
      pkgs,
      modulesPath,
      ...
    }:
    {
      imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

      fileSystems."/mnt/ssd" = {
        device = "/dev/disk/by-uuid/44444444-4444-4444-8888-888888888888";
        fsType = "ext4";
        options = [
          "nofail"
          "noatime"
        ];
      };

      fileSystems."/mnt/hdd" = {
        device = "/dev/disk/by-uuid/dee864cb-6a3c-496f-a928-dc6bf3869ce1";
        fsType = "ext4";
        options = [
          "nofail"
          "noatime"
        ];
      };

      packages = with pkgs; [ mergerfs ];

      fileSystems."/data/shared" = {
        device = "/mnt/ssd:/mnt/hdd:/mnt/nvme";
        fsType = "fuse.mergerfs";
        depends = [
          "/mnt/ssd"
          "/mnt/hdd"
          "/mnt/nvme"
        ];
        options = [
          "nofail"
          "allow_other"
          "use_ino"
          "cache.files=partial"
          "dropcacheonclose=true"
          "category.create=mfs"
          "fsname=mergerfs"
          "minfreespace=10G"
        ];
      };

      boot.kernelParams = [
        # disable broken UAS for ssh and hdd
        "usb-storage.quirks=0bda:9201:u,152d:0578:u"

        # Force use of the thinkpad_acpi driver for backlight control.
        # This allows the backlight save/load systemd service to work.
        "acpi_backlight=native"
      ];

      boot.blacklistedKernelModules = [ "pcspkr" ];
      boot.initrd.availableKernelModules = [
        "nvme"
        "xhci_pci"
        "usb_storage"
        "sd_mod"
        "aesni_intel"
        "cryptd"
      ];
      boot.initrd.kernelModules = [ ];
      boot.kernelModules = [ "kvm-amd" ];
      boot.extraModulePackages = [ ];

      # Enables DHCP on each ethernet and wireless interface. In case of scripted networking
      # (the default) this is the recommended approach. When using systemd-networkd it's
      # still possible to use this option, but it's recommended to use it in conjunction
      # with explicit per-interface declarations with `networking.interfaces.<interface>.useDHCP`.
      networking.useDHCP = lib.mkDefault true;
      # networking.interfaces.enp2s0.useDHCP = lib.mkDefault true;
      # networking.interfaces.wlp3s0.useDHCP = lib.mkDefault true;

      nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
      hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
    };
}
