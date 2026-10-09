{ inputs, ... }:

{
  flake.modules.nixos.woz =
    {
      lib,
      config,
      pkgs,
      modulesPath,
      ...
    }:
    let
      dpmsKick = pkgs.writeShellScript "dpms-kick" ''
        ${lib.getExe pkgs.wlopm} --off '*'
        ${lib.getExe pkgs.wlopm} --on '*'
      '';

      # kernels are cross built from my desktop
      crossPkgs = import inputs.apple-silicon.inputs.nixpkgs {
        localSystem = "x86_64-linux";
        crossSystem = "aarch64-linux";
        overlays = [
          inputs.apple-silicon.overlays.default
        ];
      };

      linuxAsahi = crossPkgs.linux-asahi.kernel.overrideAttrs (old: {
        makeFlags = (old.makeFlags or [ ]) ++ [ "-j20" ];
      });
    in
    {
      imports = [
        (modulesPath + "/installer/scan/not-detected.nix")
      ];

      boot.initrd.availableKernelModules = [
        "usb_storage"
        "usbhid"
      ];

      nixpkgs.overlays = [
        (final: prev: {
          # silent uboot
          uboot-asahi = prev.uboot-asahi.overrideAttrs (old: {
            postPatch =
              (old.postPatch or "")
              +
              # bash
              ''
                cat >> configs/${old.defconfig} <<'EOF'
                CONFIG_SILENT_CONSOLE=y
                CONFIG_BOOTDELAY=1
                EOF
                # force silent
                sed -i '/static bool console_update_silent(void)/,/^}/ s/^{/{\n\tgd->flags |= GD_FLG_SILENT;\n\treturn false;/' common/console.c

                # suppress the uboot version info line
                sed -i '/^int console_announce_r(void)/,/^}/ s/^{/{\n\tif (gd->flags \& GD_FLG_SILENT)\n\t\treturn 0;/' common/console.c

                # suppress uboot image
                sed -i 's/ret = show_splash(dev);/ret = 0;/g' drivers/video/video-uclass.c
              '';
          });
        })
      ];

      hardware.asahi = {
        enable = true;
        avd.enable = false;
        peripheralFirmwareDirectory = inputs.asahi-firmware;
      };

      packages = [ pkgs.unstable.avd-fw ];

      boot.kernelPackages = lib.mkForce (
        (pkgs.linuxPackagesFor linuxAsahi).extend (
          _: _: {
            inherit (pkgs.linuxPackages) cpupower;
          }
        )
      );

      persist.directories = [
        "/root/.ssh"
      ];

      # NOTE: for next build: override kernels to use 20 cores explicitely, maybe don't use the nixpkgs from the apple-silicon input to save a nixpkgs instance ig
      nix.buildMachines = [
        {
          hostName = "cray";
          systems = [ "x86_64-linux" ];
          protocol = "ssh-ng";

          maxJobs = 2;

          sshUser = config.me.user;
          sshKey = "/root/.ssh/nix_builder";
          supportedFeatures = [
            "benchmark"
            "big-parallel"
            "kvm"
            "nixos-test"
          ];
        }
      ];

      nix.distributedBuilds = true;

      me.desktop.startup.dpms-kick.cmd = "${dpmsKick}";

      boot.initrd.kernelModules = [ ];
      boot.kernelModules = [ ];
      boot.extraModulePackages = [ ];

      nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
    };
}
