{
  flake.modules.generic.custom =
    {
      lib,
      config,
      ...
    }:
    let
      cfg = config.tinted;
      modes = [
        "dark"
        "light"
      ];

      palette =
        mode: stripHash:
        (if stripHash then cfg.hex.${mode} else cfg.colors.${mode})
        // {
          _theme = mode;
        };

      deepMerge =
        a: b:
        if lib.isAttrs a && lib.isAttrs b then
          lib.zipAttrsWith
            (_: values: builtins.foldl' deepMerge (builtins.head values) (builtins.tail values))
            [
              a
              b
            ]
        else if lib.isList a && lib.isList b then
          a ++ b
        else
          b;

      mergeAttrs = builtins.foldl' deepMerge { };

      mergeable =
        {
          name,
          check,
          merge,
        }:
        lib.types.mkOptionType {
          inherit name;
          description = "palette -> ${name}, or plain ${name}";
          check = v: lib.isFunction v || check v;
          merge =
            _loc: defs:
            let
              values = map (d: d.value) defs;
            in
            if lib.any lib.isFunction values then
              mode: merge (map (v: if lib.isFunction v then v mode else v) values)
            else
              merge values;
        };

      staticAttrs = lib.types.mkOptionType {
        name = "staticAttrs";
        description = "recursively merged attribute sets";
        check = lib.isAttrs;
        merge = _loc: defs: mergeAttrs (map (d: d.value) defs);
      };

      applyPalette = value: p: if lib.isFunction value then value p else value;

      mkThemeFile =
        fileCfg: themePalette:
        let
          base =
            if fileCfg.generator != null then
              {
                value =
                  if fileCfg.themed != null then
                    deepMerge fileCfg.static (applyPalette fileCfg.themed themePalette)
                  else
                    deepMerge themePalette fileCfg.static;

                inherit (fileCfg) generator;
              }
            else if fileCfg.source != null then
              { source = applyPalette fileCfg.source themePalette; }
            else if fileCfg.text != null then
              { text = applyPalette fileCfg.text themePalette; }
            else
              throw "tinted: must specify one of text, source, or generator";
        in
        base
        // lib.optionalAttrs fileCfg.executable {
          executable = true;
        };
    in
    {
      options.tinted = {
        enable = lib.mkEnableOption "themed configuration management";

        palette = lib.mkOption {
          type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
          default = { };
          description = "Per-color palette entries. Values should include the # symbol.";
        };

        colors = lib.mkOption {
          type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
          internal = true;
          default = lib.genAttrs modes (mode: lib.mapAttrs (_: v: v.${mode}) cfg.palette);
        };

        hex = lib.mkOption {
          type = lib.types.attrsOf (lib.types.attrsOf lib.types.str);
          internal = true;
          default = lib.mapAttrs (_: lib.mapAttrs (_: lib.removePrefix "#")) cfg.colors;
        };

        user = lib.mkOption {
          type = lib.types.str;
        };

        homeDir = lib.mkOption {
          type = lib.types.str;
          default = "/home/${config.tinted.user}";
        };

        stateDir = lib.mkOption {
          type = lib.types.str;
          default = ".local/state/tinted";
        };

        files = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                executable = lib.mkEnableOption "";

                text = lib.mkOption {
                  type = lib.types.nullOr (mergeable {
                    name = "string";
                    check = lib.isString;
                    merge = lib.concatStrings;
                  });
                  default = null;
                };

                source = lib.mkOption {
                  type = lib.types.nullOr (lib.types.functionTo lib.types.path);
                  default = null;
                };

                generator = lib.mkOption {
                  type = lib.types.nullOr (lib.types.functionTo (lib.types.either lib.types.str lib.types.path));
                  default = null;
                };

                themed = lib.mkOption {
                  type = lib.types.nullOr (mergeable {
                    name = "attrs";
                    check = lib.isAttrs;
                    merge = mergeAttrs;
                  });
                  default = null;
                };

                static = lib.mkOption {
                  type = staticAttrs;
                  default = { };
                };

                stripHash = lib.mkOption {
                  type = lib.types.bool;
                  default = false;
                };
              };
            }
          );
          default = { };
          example = lib.literalExpression ''
            {
              ".Xresources".text = palette: '''
                *bg0: ''${palette.red}
                *red: ''${palette.red}
              ''';
            }
          '';
        };

        _activations = lib.mkOption {
          type = lib.types.attrsOf lib.types.attrs;
          internal = true;
          default = lib.mapAttrs (targetPath: _: {
            dirs = [
              (dirOf "${cfg.homeDir}/${targetPath}")
              (dirOf "${cfg.homeDir}/${cfg.stateDir}/${targetPath}")
            ];
            source = "${cfg.homeDir}/${cfg.stateDir}/${targetPath}-dark";
            target = "${cfg.homeDir}/${targetPath}";
          }) cfg.files;
        };
      };

      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = cfg.palette != { };
            message = "tinted: palette is empty";
          }
          {
            assertion = lib.all (variants: lib.attrNames variants == modes) (lib.attrValues cfg.palette);
            message = "tinted: every color must define exactly dark and light values";
          }
          {
            assertion = lib.all (
              file:
              lib.count (x: x != null) [
                file.text
                file.source
                file.generator
              ] == 1
            ) (lib.attrValues cfg.files);
            message = "tinted: each file must specify exactly one of text, source, or generator";
          }
          {
            assertion = lib.all (file: (file.static == { } && file.themed == null) || file.generator != null) (
              lib.attrValues cfg.files
            );
            message = "tinted: static and themed values require a generator";
          }
        ];

        hj.files = lib.concatMapAttrs (
          targetPath: fileCfg:
          lib.mergeAttrsList (
            map (mode: {
              "${cfg.stateDir}/${targetPath}-${mode}" = mkThemeFile fileCfg (palette mode fileCfg.stripHash);
            }) modes
          )
        ) cfg.files;
      };
    };

  flake.modules.nixos.custom =
    { config, lib, ... }:
    {
      systemd.user.tmpfiles.rules = lib.concatMap (
        v:
        map (d: "d ${d} 0755 ${config.me.user} users - -") v.dirs ++ [ "L ${v.target} - - - - ${v.source}" ]
      ) (lib.attrValues config.tinted._activations);
    };

  flake.modules.darwin.custom =
    { config, lib, ... }:
    {
      activation = lib.concatMapStringsSep "\n" (v: ''
        ${lib.concatMapStringsSep "\n" (d: "mkdir -p ${d}") v.dirs}
        ln -s ${v.source} ${v.target} 2> /dev/null || true
        chown -h ${config.me.user} ${v.target}
      '') (lib.attrValues config.tinted._activations);
    };
}
