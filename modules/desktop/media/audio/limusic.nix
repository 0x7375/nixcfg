{
  flake.modules.nixos.desktop =
    { pkgs, lib, ... }:
    let
      version = "1.4.0-rc.4";

      desktopItem = pkgs.makeDesktopItem {
        name = "limusic";
        desktopName = "Limusic";
        genericName = "Music Player";
        comment = "YouTube Music desktop client";
        exec = "limusic";
        icon = "audio-x-generic";
        terminal = false;
        categories = [
          "AudioVideo"
          "Audio"
          "Player"
        ];
      };

      limusic = pkgs.appimageTools.wrapType2 {
        pname = "limusic";
        inherit version;

        src = pkgs.fetchurl {
          url = "https://github.com/SimoHypers/limusic/releases/download/v${version}/limusic_${version}_amd64.AppImage";
          hash = "sha256-a6HZKoyTa1EAfobEm5eLRgTnp3gPQU9mN8M7+VyaDX8=";
        };

        extraInstallCommands = ''
          install -Dm644 \
            ${desktopItem}/share/applications/limusic.desktop \
            $out/share/applications/limusic.desktop
        '';

        meta = {
          description = "Native desktop YouTube Music client";
          homepage = "https://github.com/SimoHypers/limusic";
          license = lib.licenses.gpl3Only;
          platforms = [
            "x86_64-linux"
            "aarch64-linux"
            "aarch64-darwin"
          ];
          mainProgram = "limusic";
        };
      };
    in
    {
      packages = [ limusic ];
    };
}
