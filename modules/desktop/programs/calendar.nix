{
  flake.modules.generic.desktop =
    {
      config,
      pkgs,
      ...
    }:
    let
      inherit (config.me) home;

      mkAccount =
        {
          name,
          host,
          url,
          username,
        }:
        # ini
        ''
          [Autoconfig]
          Revision=${builtins.hashString "sha256" "${name}:${url}:${username}"}

          [Data Source]
          DisplayName=${name}
          Enabled=true
          Parent=

          [Collection]
          BackendName=webdav
          CalendarEnabled=true
          ContactsEnabled=false
          MailEnabled=false
          Identity=${username}
          CalendarUrl=${url}

          [Authentication]
          Host=${host}
          Method=plain/password
          Port=443
          User=${username}
          RememberPassword=true
          IsExternal=false

          [Security]
          Method=tls
        '';
    in
    {
      packages = [ pkgs.gnome-calendar ];

      programs.dconf = {
        profiles.user.databases = [
          {
            settings."org/gnome/evolution-data-server" = {
              autoconfig-directory = "${home}/.config/evolution-data-server/autoconfig";
            };
          }
        ];
      };

      services.gnome.evolution-data-server.enable = true;

      hj.xdg.config.files = {
        "evolution-data-server/autoconfig/radicale.source".text = mkAccount {
          name = "Radicale";
          host = "dav.0xaa.me";
          url = "https://dav.0xaa.me/admin/";
          username = "admin";
        };

        "evolution-data-server/autoconfig/unicaen.source".text = mkAccount {
          name = "UniCaen";
          host = "webmail.unicaen.fr";
          url = "https://webmail.unicaen.fr/dav/22205529@etu.unicaen.fr/";
          username = "22205529@etu.unicaen.fr";
        };
      };
    };
}
