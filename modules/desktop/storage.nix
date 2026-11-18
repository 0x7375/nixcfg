{ self, ... }:
{
  flake.modules.nixos.desktop =
    {
      lib,
      pkgs,
      ...
    }:
    {
      services.udisks2 = {
        enable = true;
        package = pkgs.udisks.override {
          exfat = pkgs.exfatprogs;
        };
      };

      persistUser.directories = [ ".config/kdeconnect" ];

      packages = with pkgs; [
        nemo
        ntfs3g
        exfat
        xarchiver
        glib
      ];

      programs.kdeconnect.enable = true;

      systemd.user.services.kdeconnect = {
        wantedBy = [ "graphical-session.target" ];
        after = [ "graphical-session.target" ];
        serviceConfig = {
          ExecStart = lib.getExe' pkgs.kdePackages.kdeconnect-kde "kdeconnectd";
        };
      };

      xdg.mimeApps.defaultApplications = self.lib.mapMimeEntries [
        "application/bzip2"
        "application/gzip"
        "application/zip"
        "application/vnd.rar"
        "application/x-7z-compressed-tar"
        "application/x-bzip"
        "application/x-bzip2"
        "application/x-bzip2-compressed-tar"
        "application/x-bzip-compressed-tar"
        "application/x-compress"
        "application/x-compressed-tar"
        "application/x-cpio"
        "application/x-lha"
        "application/x-lzip"
        "application/x-lzip-compressed-tar"
        "application/x-lzma"
        "application/x-lzma-compressed-tar"
        "application/x-rar-compressed"
        "application/x-tarz"
        "application/x-xar"
        "application/x-xz"
        "application/x-xz-compressed-tar"
        "application/x-zstd-compressed-tar"
        "application/zstd"
      ] "xarchiver";
    };

  flake.modules.darwin.desktop =
    {
      pkgs,
      ...
    }:
    let
      kdeconnect-nightly = pkgs.stdenv.mkDerivation rec {
        pname = "kdeconnect-nightly";
        version = "6325";
        src = pkgs.fetchurl {
          url = "https://origin.cdn.kde.org/ci-builds/network/kdeconnect-kde/master/macos-arm64/kdeconnect-kde-master-${version}-macos-clang-arm64.dmg";
          hash = "sha256-f5CLB/pP8AXSdrL9rn8kt8O3odJtqm8bXhpVudauKeE=";
        };
        nativeBuildInputs = [ pkgs.undmg ];
        sourceRoot = ".";
        installPhase = ''
          mkdir -p $out/Applications
          cp -r *.app $out/Applications
        '';
      };
    in
    {
      packages = [ kdeconnect-nightly ];
    };
}
