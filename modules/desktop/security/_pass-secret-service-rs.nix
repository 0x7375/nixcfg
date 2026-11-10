{ pkgs, ... }:

pkgs.rustPlatform.buildRustPackage rec {
  pname = "pass-secret-service";
  version = "0.7.1";

  src = pkgs.fetchFromGitHub {
    owner = "grimsteel";
    repo = "pass-secret-service";
    tag = "v${version}";
    hash = "sha256-K98T+YH58GkZQJEvkT9ciEIGYOv5oCxOhatdZXxOqvU=";
  };

  cargoHash = "sha256-PIhTigOrqwzdxQ4zmbgjc5caLH8GXHRl89Se1N1Jjnw=";

  postInstall = ''
    install -Dm644 systemd/org.freedesktop.secrets.service \
    $out/share/dbus-1/services/org.freedesktop.secrets.service
    install -Dm644 systemd/pass-secret-service.service \
    $out/lib/systemd/user/pass-secret-service.service
    substituteInPlace $out/share/dbus-1/services/org.freedesktop.secrets.service \
    $out/lib/systemd/user/pass-secret-service.service \
    --replace-fail "/usr/bin" "$out/bin"
  '';

  meta = {
    description = "Implementation of org.freedesktop.secrets using pass";
    homepage = "https://github.com/grimsteel/pass-secret-service";
    license = pkgs.lib.licenses.gpl3Only;
    maintainers = [ ];
    mainProgram = "pass-secret-service";
  };
}
