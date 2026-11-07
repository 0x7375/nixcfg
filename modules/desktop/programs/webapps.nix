{
  flake.modules.nixos.desktop =
    {
      pkgs,
      lib,
      ...
    }:
    {
      xdg.desktopEntries = {
        bitwarden = {
          exec = "${lib.getExe pkgs.helium} --app=http://vault.bitwarden.com";
          name = "Bitwarden";
          type = "Application";
          icon = "bitwarden";
        };
      };

      me.desktop =
        let
          type = "appid";
        in
        {
          assign = [
            {
              inherit type;
              name = "vault.bitwarden.com";
              workspace = "2";
            }
          ];
          floating = [
            {
              inherit type;
              name = "vault.bitwarden.com";
              enable = false;
            }
          ];
        };
    };
}
