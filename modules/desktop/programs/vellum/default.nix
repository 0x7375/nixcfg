{
  flake.modules.nixos.desktop =
    { config, lib, ... }:
    let
      vellum = lib.getExe config.services.vellum.package;
    in
    {
      services.vellum.enable = true;

      me.desktop.bindings = {
        "Mod+o" = "${vellum} toggle";
        "Shift+F9" = "${vellum} toggle";
      };
    };
}
