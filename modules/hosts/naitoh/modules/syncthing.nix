{
  flake.modules.nixos.naitoh =
    {
      lib,
      config,
      ...
    }:
    let
      inherit (config.me) hostname services;
      inherit (services.syncthing) port;
    in
    {
      me.services.syncthing = {
        subdomain = "sync";
        port = 8384;
      };

      me.hostSecrets."syncthing/key".owner = "syncthing";
      sops.secrets.syncthing_pw.owner = "syncthing";

      users.users.syncthing.extraGroups = [ "media" ];

      me.syncthing.dataRoot = "/data/main/syncthing/";

      persist.directories = [ "/var/lib/syncthing" ];

      services.syncthing = {
        enable = lib.mkForce true;
        guiAddress = "0.0.0.0:${toString port}";
        openDefaultPorts = true;
        settings.devices =
          let
            syncthingHosts = lib.filterAttrs (n: v: v.syncthing.id != null && n != hostname) config.me.hosts;
          in
          lib.mapAttrs (_: v: { inherit (v.syncthing) id; }) syncthingHosts;
      };

      systemd.tmpfiles.settings.syncthing."/data/main/syncthing".d = {
        group = "syncthing";
        mode = "0755";
        user = "syncthing";
      };
    };
}
