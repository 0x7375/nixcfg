{
  flake.modules.generic.core =
    {
      lib,
      pkgs,
      config,
      ...
    }:
    let
      inherit (config.me)
        hosts
        host
        ;

      github = pkgs.writeText "github" ''
        [user]
          email = "github.little@0xaa.me"
          name = "0x7375"
      '';
      sourcehut = pkgs.writeText "sourcehut" ''
        [user]
          email = "sourcehut.buckshot@0xaa.me"
          name = "ayko"
      '';
      codeberg = pkgs.writeText "codeberg" ''
        [user]
          email = "codeberg.unmapped@0xaa.me"
          name = "0x7E"
      '';

    in
    {
      packages = with pkgs; [
        git
        difftastic
      ];

      vars.DFT_COLOR = "always";

      hj.xdg.config.files."git/ignore".text = ''
        .DS_Store
      '';

      hj.xdg.config.files."git/config".text =
        # git_config
        ''
          [alias]
            resign = !git commit -S -F .git/COMMIT_EDITMSG --cleanup=strip

          [commit]
            gpgsign = true

          [credential]
            helper = "store"

          [diff]
            external = "difft"

          [gpg]
            format = "ssh"

          [gpg "openpgp"]
            program = "${lib.getExe' pkgs.gnupg "gpg"}"

          [gpg "ssh"]
            allowedSignersFile = "~/.ssh/allowed_signers"

          [init]
            defaultBranch = "main"

          [url "git@codeberg.org:"]
            insteadOf = "codeberg:"

          [url "git@git.sr.ht:"]
            insteadOf = "sourcehut:"

          [url "git@git.unicaen.fr:"]
            insteadOf = "uni:"

          [url "git@github.com:"]
            insteadOf = "github:"

          [url "https://codeberg.org/"]
            insteadOf = "cb:"

          [url "https://git.sr.ht/"]
            insteadOf = "sh:"

          [url "https://github.com/"]
            insteadOf = "gh:"

          [url "https://redmine-etu.unicaen.fr/git/"]
            insteadOf = "forge:"

          [user]
            signingkey = "${pkgs.writeText "key.pub" host.sshKey.public}"

          [includeIf "hasconfig:remote.*.url:github:*/**"]
            path = "${github}"

          [includeIf "hasconfig:remote.*.url:gh:*/**"]
            path = "${github}"

          [includeIf "hasconfig:remote.*.url:sourcehut:*/**"]
            path = "${sourcehut}"

          [includeIf "hasconfig:remote.*.url:sh:*/**"]
            path = "${sourcehut}"

          [includeIf "hasconfig:remote.*.url:codeberg:*/**"]
            path = "${codeberg}"

          [includeIf "hasconfig:remote.*.url:cb:*/**"]
            path = "${codeberg}"
        '';

      hj.files.".ssh/allowed_signers".text = lib.concatMapStrings (k: "* ${k}\n") [
        hosts.mainKey.sshKey.public
        hosts.backupKey.sshKey.public
        hosts.mach.sshKey.public
      ];
    };

  flake.modules.darwin.core =
    { config, ... }:
    let
      inherit (config.me) home;
      secretivePath = "${home}/Library/Containers/com.maxgoedjen.Secretive.SecretAgent/Data/socket.ssh";
    in
    {
      hj.xdg.config.files."ssh/config".text = ''
        Host *
          IdentityAgent ${secretivePath}
      '';

      environment.shellInit = ''
        export SSH_AUTH_SOCK=${secretivePath}
      '';
    };

  flake.modules.nixos.core =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      inherit (config.me) host;
    in
    {
      systemd.user.services.ssh-add = {
        description = "Add keys to SSH agent";
        after = [ "ssh-agent.service" ];
        bindsTo = [ "ssh-agent.service" ];
        upheldBy = [ "ssh-agent.service" ];

        serviceConfig = {
          Type = "oneshot";
          ExecStartPre = "${lib.getExe' pkgs.coreutils "sleep"} 1";
          Environment = "SSH_AUTH_SOCK=%t/ssh-agent";
          ExecStart = "${lib.getExe' pkgs.openssh "ssh-add"} ${host.sshKey.privatePath}";
          RemainAfterExit = "yes";
        };
      };

      systemd.user.services.ssh-agent = {
        wantedBy = [ "default.target" ];
        description = "SSH authentication agent";
        documentation = [ "man:ssh-agent(1)" ];
        serviceConfig.ExecStart = "${lib.getExe' pkgs.openssh "ssh-agent"} -D -a %t/ssh-agent";
      };

      environment.shellInit =
        # bash
        ''
          if [ -z "$SSH_AUTH_SOCK" ]; then
            export SSH_AUTH_SOCK=$XDG_RUNTIME_DIR/ssh-agent
          fi
        '';
    };

  flake.modules.generic.secrets =
    {
      config,
      lib,
      ...
    }:
    let
      inherit (config.me) user;
    in
    {
      sops.secrets.full_name.owner = user;
      sops.secrets.uni_email.owner = user;
      sops.templates."uni-git-config.ini" = {
        owner = user;
        content =
          # ini
          ''
            [user]
            name = ${config.sops.placeholder.full_name}
            email = ${config.sops.placeholder.uni_email}
          '';
      };

      hj.xdg.config.files."git/config".text = lib.mkAfter ''
        [includeIf "hasconfig:remote.*.url:uni:*/**"]
          path = ${config.sops.templates."uni-git-config.ini".path}
        [includeIf "hasconfig:remote.*.url:forge:**"]
          path = ${config.sops.templates."uni-git-config.ini".path}
      '';
    };
}
