{
  lib,
  appimageTools,
  fetchurl,
}:

let
  pname = "meiro";
  version = "0.6.1";

  src = fetchurl {
    url = "https://github.com/elianiva/meiro/releases/download/desktop-v${version}/Meiro-${version}-linux-amd64.AppImage";
    hash = "sha256-2R1WZAWwe0vTiI1GgqGRNHioVHHhNKaPjsYLA00c8BU=";
  };

  appimageContents = appimageTools.extract {
    inherit pname version src;
  };

in
appimageTools.wrapType2 {
  inherit pname version src;

  extraPkgs =
    pkgs: with pkgs; [
      webkitgtk_4_1
      libayatana-appindicator
    ];

  profile = ''
    export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
  '';

  extraBwrapArgs = [
    "--ro-bind-try /etc/egl/egl_external_platform.d /etc/egl/egl_external_platform.d"
  ];

  extraInstallCommands =
    # bash
    ''
          # Reuse the upstream desktop entry when available.
          install -d "$out/share/applications"

          desktopFile="$(
            find ${appimageContents} -type f \
              -iname '*meiro*.desktop' -print -quit
          )"

          if [ -n "$desktopFile" ]; then
            install -Dm644 "$desktopFile" \
              "$out/share/applications/${pname}.desktop"

            sed -i \
              -e 's|^Exec=.*|Exec=meiro|' \
              -e 's|^TryExec=.*|TryExec=meiro|' \
              "$out/share/applications/${pname}.desktop"
          else
            cat > "$out/share/applications/${pname}.desktop" <<'EOF'
      [Desktop Entry]
      Name=Meiro
      Comment=YouTube Music desktop client
      Exec=meiro
      Icon=meiro
      Terminal=false
      Type=Application
      Categories=AudioVideo;Audio;Player;
      EOF
          fi

          if [ -d "${appimageContents}/usr/share/icons" ]; then
            install -d "$out/share/icons"
            cp -a "${appimageContents}/usr/share/icons/." "$out/share/icons/"
          fi

          if [ -d "${appimageContents}/usr/share/pixmaps" ]; then
            install -d "$out/share/pixmaps"
            cp -a "${appimageContents}/usr/share/pixmaps/." "$out/share/pixmaps/"
          fi

          if [ -f "${appimageContents}/.DirIcon" ]; then
            install -Dm644 "${appimageContents}/.DirIcon" \
              "$out/share/pixmaps/meiro.png"
          fi
    '';

  meta = {
    description = "Lightweight YouTube Music desktop client";
    homepage = "https://github.com/elianiva/meiro";
    license = lib.licenses.gpl3Only;
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
  };
}
