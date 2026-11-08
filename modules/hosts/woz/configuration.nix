{ self, inputs, ... }:

{
  flake.modules.nixos.woz =
    {
      mv,
      lib,
      ...
    }:
    {
      imports = [
        inputs.apple-silicon.nixosModules.apple-silicon-support
        inputs.titdb.nixosModules.default
      ];

      services.titdb = {
        enable = true;
        device = "/dev/input/event2";
      };

      nix.settings = {
        cores = 4;
        max-jobs = 1;
      };

      boot.extraModprobeConfig = "options hid_apple swap_fn_leftctrl=1";

      powerManagement.resumeCommands =
        # bash
        ''
          # https://github.com/AsahiLinux/linux/issues/497
          # broken rn..........
          # force usb to disconnect/reconnect
          ${lib.getExe (self.lib.withMainProgram "tuxvdmtool" (mv.version "tuxvdmtool" "0.2.0-unstable-2026-03-15"))} disconnect || true
        '';

      system.stateVersion = "25.11";
    };
}
