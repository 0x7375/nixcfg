{ self, inputs, ... }:

{
  flake.modules.generic.core =
    {
      lib,
      pkgs,
      ...
    }:
    {
      imports = with lib; [
        (mkAliasOptionModule [ "packages" ] [ "environment" "systemPackages" ])
        (mkAliasOptionModule [ "vars" ] [ "environment" "variables" ])
        (mkAliasOptionModule [ "aliases" ] [ "environment" "shellAliases" ])
        (mkAliasOptionModule [ "activation" ] [ "system" "activationScripts" "postActivation" "text" ])
        (mkAliasOptionModule [ "preActivation" ] [ "system" "activationScripts" "preActivation" "text" ])
      ];

      options = {
        unfree-packages = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "List of unfree packages to allow installing.";
        };

        userActivation = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = "Alias for respective user activation method on macos/nixos, don't use single quotes on macos";
        };
      };

      config = {
        assertions = [
          {
            assertion = (self.submodules or true) == true;
            message = "Unable to build without submodules. Append '?submodules=1#' to the URI like: .?submodules=1#host";
          }
        ];

        environment.etc.nixcfg.source = pkgs.lib.cleanSource self;

        programs.nix-index-database.comma.enable = true;
        programs.nix-index.enable = true;
      };
    };

  flake.modules.nixos.docker =
    { pkgs, ... }:
    {
      virtualisation.podman = {
        enable = true;
        dockerSocket.enable = true;
        dockerCompat = true;
      };

      packages = [ pkgs.docker-compose ];
    };

  flake.modules.darwin.core =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    {
      system.activationScripts.postActivation.text = lib.mkIf (config.userActivation != "") ''
        sudo -H -u ${config.me.user} ${lib.getExe pkgs.bash} -c '
          ${config.userActivation}
        '
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
      persist.directories = [ "/var/cache/man" ];

      services.locate.enable = true;

      security.polkit.enable = true;

      system.userActivationScripts.userActivation.text = config.userActivation;

      documentation = {
        dev.enable = true;
        man.cache = {
          enable = true;
          generateAtRuntime = true;
        };
      };

      systemd.user.services.nixcfg-setup = {
        description = "Clone dotfiles repository";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "clone-dotfiles" ''
            if [[ ! -e ${config.me.flakeDir} ]]; then
              ${lib.getExe pkgs.git} -c core.sshCommand="${lib.getExe' pkgs.openssh "ssh"} -o StrictHostKeyChecking=accept-new" clone codeberg:0x7E/nixcfg ${config.me.flakeDir}
            fi
          '';
          RemainAfterExit = true;
        };
        wantedBy = [ "default.target" ];
      };
    };

  perSystem =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      packages =
        let
          dir = ../_scripts;
          files = builtins.readDir dir;
          nixFiles = lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".nix" name) files;
        in
        lib.mapAttrs' (
          name: _:
          lib.nameValuePair (lib.removeSuffix ".nix" name) (
            pkgs.callPackage (dir + "/${name}") {
              inherit inputs;
              my = config.packages;
            }
          )
        ) nixFiles;
    };
}
