{
  flake.modules.nixos.desktop =
    {
      config,
      lib,
      ...
    }:
    let
      vellum = lib.getExe config.services.vellum.package;
    in
    {
      services.vellum = {
        enable = true;
        settings.annotations_visible = false;
      };

      me.desktop.bindings."Mod+o" = "${vellum} toggle";
    };
}
