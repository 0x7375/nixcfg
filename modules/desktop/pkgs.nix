{
  flake.modules.generic.desktop =
    {
      pkgs,
      ...
    }:
    {
      packages = with pkgs; [
        my.swap-theme
        my.backup-vault
        typst
      ];
    };

  flake.modules.nixos.desktop =
    { lib, pkgs, ... }:
    lib.mkMerge [
      {
        # unfree-packages = [ "omnissa-horizon-client" ];

        packages = with pkgs; [
          # omnissa-horizon-client
          signal-desktop
          qbittorrent
          # jetbrains.idea-community
        ];
      }
      {
        packages = [ pkgs.gaphor ];

        xdg.mimeApps.defaultApplications = {
          "application/x-gaphor" = "gaphor.desktop";
        };

        hj.xdg.data.files."mime/packages/gaphor.xml".text = # xml
          ''
            <?xml version="1.0" encoding="UTF-8"?>
            <mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
              <mime-type type="application/x-gaphor">
                <comment>Gaphor UML diagram</comment>
                <glob pattern="*.gaphor"/>
                <sub-class-of type="application/xml"/>
              </mime-type>
            </mime-info>
          '';
      }
    ];
}
