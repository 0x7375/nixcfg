{ inputs, self, ... }:

let
  root = ./../../../..;
  mkNeovim =
    {
      pkgs,
      mv,
      lsp ? true,
      unfree ? false,
    }:
    inputs.mnw.lib.wrap pkgs {
      neovim = inputs.neovim.packages.${pkgs.stdenv.hostPlatform.system}.neovim.overrideAttrs (_: {
        doCheck = false;
        doInstallCheck = false;
        patches = [
          ./allow_showcmdloc_winbar.patch
        ];
      });

      initLua = builtins.readFile (root + /nvim/init.lua);

      providers = {
        ruby.enable = false;
        python3.enable = false;
        nodeJs.enable = false;
        perl.enable = false;
      };

      plugins = {
        dev.config = {
          pure = "${root + /nvim}";
          impure = "~/.config/nixcfg/nvim";
        };

        start =
          with pkgs.vimPlugins;
          [
            # ui
            cloak-nvim
            rainbow-delimiters-nvim
            gitsigns-nvim
            nvim-highlight-colors

            # lsp
            nvim-lspconfig
            friendly-snippets
            luasnip
            conform-nvim
            blink-cmp
            neogen
            lazydev-nvim
            nvim-lint

            # nav
            fzf-lua
            oil-nvim
            harpoon2
            plenary-nvim

            # tools
            live-command-nvim
            {
              pname = "undotree";
              src = pkgs.fetchFromGitHub {
                owner = "jiaoshijie";
                repo = "undotree";
                rev = "02b69aed427b848c4dca483fc5e9524b6019c296";
                hash = "sha256-AwGFfTwYRE9aU99b14QS44n4DLnhzH5xXYZc0mb5Y/w=";
              };
            }
            vim-fugitive
            diffs-nvim
            {
              pname = "diffview-plus-nvim";
              src = pkgs.fetchFromGitHub {
                owner = "dlyongemallo";
                repo = "diffview-plus.nvim";
                rev = "e54dc97a584e1ae410da9d4898adb8224437ad63";
                hash = "sha256-xdsF8H052CKpR6KphljsEoBS9eMDDUls8Gwpt+wBcxc=";
              };
            }
            grug-far-nvim
            orgmode

            # actions
            treesj
            dial-nvim
            mini-move
            nvim-surround
            nvim-ts-autotag
            vim-indent-object
            nvim-treesitter-textobjects
            multicursor-nvim
            vim-table-mode
          ]
          ++ nvim-treesitter.withAllGrammars.dependencies
          ++ pkgs.lib.optionals unfree (
            with pkgs.vimPlugins;
            [
              ReplaceWithRegister
              vim-wordmotion
            ]
          );
      };

      extraBinPath =
        pkgs.lib.optionals lsp (
          with pkgs;
          [
            tree-sitter
            gnumake

            # LSPs
            lua-language-server
            nixd
            typescript-language-server
            jdt-language-server
            bash-language-server
            emmet-language-server
            vscode-langservers-extracted
            tailwindcss-language-server
            rustywind
            eslint
            gopls
            texlab
            sqls
            ruff
            pyright
            phpactor
            mpls

            # Formatters
            nixfmt
            stylua
            typstyle
            shfmt
            phpPackages.php-codesniffer
            rustfmt

            # Linters
            shellcheck
            statix
            deadnix
            oxlint
          ]
          ++ (
            let
              at = mv.at "2026-06-01";
            in
            [
              at.rust-analyzer
              at.cargo
              at.rustc
              at.clippy
              at.clang
              at.mold
            ]
          )
        )
        ++ pkgs.lib.optionals unfree [ pkgs.intelephense ];
    };
in
{
  perSystem =
    { pkgs, ... }:
    {
      packages.neovim = mkNeovim {
        inherit pkgs;
        mv = inputs.multiverse.multiverse.${pkgs.stdenv.hostPlatform.system}.fast;
      };
    };

  flake.modules.generic.core =
    {
      pkgs,
      mv,
      config,
      ...
    }:
    {
      unfree-packages = [
        "intelephense"
        "ReplaceWithRegister"
        "vim-wordmotion"
      ];

      packages = [
        pkgs.my.fossify
        (mkNeovim {
          inherit pkgs mv;
          lsp = false;
          unfree = true;
        })
      ];

      hj.xdg.config.files."nvim".source = "${config.me.flakeDir}/nvim";
    };

  flake.modules.darwin.desktop =
    { pkgs, mv, ... }:
    {
      packages = [
        (mkNeovim {
          inherit pkgs mv;
          unfree = true;
        }).devMode
      ];
    };

  flake.modules.nixos.desktop =
    {
      pkgs,
      mv,
      ...
    }:
    {
      packages = [
        (mkNeovim {
          inherit pkgs mv;
          unfree = true;
        }).devMode
      ];
    };

  flake.modules.nixos.core = {
    persistUser.directories = [
      ".cache/nvim"
      ".cache/mnw"
      ".local/share/nvim"
      ".local/share/mnw"
      ".local/state/nvim"
      ".local/state/mnw"
    ];

    xdg.mimeApps.defaultApplications = self.lib.mapMimeEntries [
      "text/plain"
      "text/markdown"
      "text/x-java"
      "text/x-haskell"
      "text/x-chdr"
      "text/x-csrc"
      "text/x-makefile"
      "text/x-python"
      "text/x-log"
      "text/x-readme"
      "text/x-patch"
      "text/css"
      "application/x-php"
      "application/x-desktop"
      "application/json"
      "application/xml"
      "application/x-shellscript"
    ] "nvim";
  };
}
