{ inputs, ... }:

{
  flake.modules.nixos.woz =
    {
      lib,
      modulesPath,
      ...
    }:
    {
      imports = [
        (modulesPath + "/installer/scan/not-detected.nix")
      ];

      boot.initrd.availableKernelModules = [
        "usb_storage"
        "usbhid"
      ];

      persist.directories = [ "/root/.ssh" ];

      hardware.asahi = {
        enable = true;
        peripheralFirmwareDirectory = inputs.asahi-firmware;
        # force it to use the apple-silicon nixpkgs input otherwise cache doesn't work
        pkgs = lib.mkForce (
          import inputs.apple-silicon.inputs.nixpkgs {
            system = "aarch64-linux";
            overlays = [
              inputs.apple-silicon.overlays.default
              (final: prev: {
                # silent uboot
                uboot-asahi = prev.uboot-asahi.overrideAttrs (old: {
                  postPatch =
                    (old.postPatch or "")
                    # bash
                    + ''
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
          }
        );
      };

      boot.initrd.kernelModules = [ ];
      boot.kernelModules = [ ];
      boot.extraModulePackages = [ ];

      nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";
    };
}
