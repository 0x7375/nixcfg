{
  flake.modules.generic.core =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.me) user;
      mirrorToRoot = lib.mapAttrs (
        name: file:
        (removeAttrs file [
          "target"
          "relativeTo"
        ])
        // {
          target = name;
        }
      );
    in
    {
      imports = [
        (lib.mkAliasOptionModule [ "hj" ] [ "hjem" "users" config.me.user ])
      ];

      hjem = {
        users.${user}.enable = true;
        users.root = {
          enable = true;
          files = mirrorToRoot config.hjem.users.${user}.files;
          xdg.config.files = mirrorToRoot config.hjem.users.${user}.xdg.config.files;
        };
        clobberByDefault = true;
      };

      activation = ''
        ${lib.getExe' pkgs.systemd "systemctl"} start hjem-activate@root.service || true
      '';
    };

  flake.modules.nixos.core =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    {
      persist.directories = [ "/var/lib/hjem" ];

      users.users.${config.me.user} = {
        inherit (config.me) uid home;
        isNormalUser = true;
        initialPassword = "pw123";
        initialHashedPassword = lib.mkForce null;
        shell = pkgs.zsh;
        extraGroups = [
          "wheel"
          "input"
        ];
      };

      users.users.root = {
        initialPassword = "root";
        initialHashedPassword = lib.mkForce null;
        shell = pkgs.zsh;
      };
    };

  flake.modules.nixos.secrets =
    {
      lib,
      config,
      ...
    }:
    {
      users.mutableUsers = false;

      sops.secrets.user_pw.neededForUsers = true;
      sops.secrets.root_pw.neededForUsers = true;

      users.users.${config.me.user} = {
        initialPassword = lib.mkForce null;
        hashedPasswordFile = config.sops.secrets.user_pw.path;
      };

      users.users.root = {
        initialPassword = lib.mkForce null;
        hashedPasswordFile = config.sops.secrets.root_pw.path;
      };
    };
}
