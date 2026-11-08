{ self, ... }:

{
  flake.modules.generic.core =
    {
      lib,
      config,
      pkgs,
      mv,
      ...
    }:
    let
      inherit (pkgs.stdenv) isLinux;
      previewer = lib.getExe (import ./_previewer.nix { inherit isLinux pkgs; });
    in
    {
      nixpkgs.overlays = [
        (final: prev: {
          lf = self.lib.withMainProgram "lf" (mv.version "lf" "42");

          ouch = (prev.crossPkgs or prev).ouch.override {
            enableUnfree = true;
          };
        })
      ];

      unfree-packages = [ "ouch" ];

      packages = with pkgs; [
        lf
        ouch
        perlPackages.FileMimeInfo
        chafa
      ];

      hj.xdg.config.files."lf/lfrc".text =
        let
          inherit (config.me)
            user
            uid
            home
            ;
          inherit (lib) getExe getExe';
          no-confirm = keys: lib.concatStringsSep "\n" (map (key: "vmap ${key} visual-toggle ${key}") keys);
          open = "${lib.optionalString isLinux "mime"}open";
        in
        # bash
        ''
          set previewer ${previewer}
          set filesep "\n"
          set hidden
          set noicons
          set ifs "\n"
          set ignorecase
          set info
          set promptfmt "\033[34;1m%d\033[0m\033[1m%f\033[0m"
          set errorfmt "\033[7;31m" # overriden to use background color as foreground
          set ratios "1:1"
          set scrolloff 8
          set shell "zsh"
          set shellopts "-euy"
          set sortby "ext"
          set tabstop 4

          cmd on-select &{{
            ${getExe pkgs.lf} -remote "send $id redraw"
          }}
          cmd on-cd &{{
            if [ -d .git ] || [ -f .git ]; then
                branch="$(git branch --show-current 2>/dev/null)" || true
                fmt="\033[34;1m%d\033[0m\033[1m%f\033[0m \033[32;1mgit:$branch\033[0m"
            else
                fmt="\033[34;1m%d\033[0m\033[1m%f\033[0m"
            fi
            ${getExe pkgs.lf} -remote "send $id set promptfmt \"$fmt\""
          }}
          cmd on-focus-gained :{{
            set cursorparentfmt "\033[7m"
            set cursoractivefmt "\033[7m"
            set cursorpreviewfmt "\033[4m"
          }}
          cmd on-focus-lost :{{
            set cursorparentfmt ""
            set cursoractivefmt ""
            set cursorpreviewfmt ""
          }}

          map , find-prev
          map . set hidden!
          map / search
          map ; find-next
          map <c-d> half-down

          cmd fzf_jump ''${{
              res="$(${getExe pkgs.fd} . | ${getExe pkgs.fzf} --reverse --header="Jump to location" || true)"
              if [ -n "$res" ]; then
                  if [ -d "$res" ]; then
                      cmd="cd"
                  else
                      cmd="select"
                  fi
                  res="$(printf '%s' "$res" | sed 's/\\/\\\\/g;s/"/\\"/g')"
                  lf -remote "send $id $cmd \"$res\""
              fi
          }}

          map <c-t> fzf_jump

          cmd mount-archive ''${{
            if ${getExe pkgs.file} --mime-type "$f" | grep -qE 'application/zip|application/x-tar|application/x-7z-compressed|application/octet-stream|application/gzip'; then
              mntdir="''${f}.mnt"
              mkdir -p "$mntdir"
              ${getExe pkgs.archivemount} "$f" "$mntdir"
              ${getExe pkgs.lf} -remote "send $id cd $mntdir"
            fi
          }}

          map <c-l> mount-archive

          cmd move-to-new-dir %{{
            printf "Directory name: "
            read newd
            if [[ -z $newd ]]; then
              ${getExe pkgs.lf} -remote "send $id reload"
              return;
            fi

            mkdir -p -- "$newd"
            mv -- $fx "$newd"
          }}

          map <c-n> move-to-new-dir
          map <c-o> jump-prev
          map <c-p> ''${{
            cols=$(tput cols)
            lines=$(tput lines)
            ${previewer} "$f" "$cols" "$lines" 0 0 | less -R
          }}
          map <c-r> redraw
          map <c-u> half-up
          map <c-z> $kill -STOP $PPID
          map <enter> open
          map <pgdn>
          map <pgup>
          map <space> $\${open} --ask $f
          map <tab> jump-next

          cmd toggle-executable ''${{
            [[ -x $f ]] && chmod -x "$f" || chmod +x "$f"
            ${getExe pkgs.lf} -remote 'send reload'
          }}

          map = toggle-executable
          map ? search-back
          map A :rename; cmd-end
          map C clear
          map D delete
          map E $sudoedit $f
          map F find-back
          map G bottom

          map I :rename; cmd-home
          map J :updir; down; open
          map K :updir; up; open
          map L
          map M
          map N search-prev
          map O &${getExe pkgs.ripdrag} $fx

          cmd paste-overwrite %{{
              mode=$(head -1 ~/.local/share/lf/files)
              list=$(${getExe' pkgs.gnused "sed"} 1d ~/.local/share/lf/files)
              if [[ $mode == "copy" ]]; then
                  cp -r $list .
              elif [[ $mode == "move" ]]; then
                  mv $list .
              fi
              ${getExe pkgs.lf} -remote 'send load'
              ${getExe pkgs.lf} -remote 'send clear'
              ${getExe pkgs.lf} -remote "send $id reload"
          }}

          map P paste-overwrite

          cmd quit-and-cd ''${{
            # absolute paths are needed since we can be in a mount point
            LF_CD_FILE=''${LF_CD_FILE:-/dev/null}
            path=$(pwd)
            
            # make sure we are not in a mount point
            while [[ $path == *".mnt"* ]]; do
              path=$(${getExe' pkgs.coreutils "dirname"} "$path")
            done
            
            echo "$path" > "$LF_CD_FILE"
            ${getExe pkgs.lf} -remote "send $id quit"
          }}

          map Q quit-and-cd
          map R :source ${home}/.config/lf/lfrc; reload

          cmd su ''${{
            ${getExe pkgs.lf} -remote "send $id quit"
            sudo lf
          }}

          map S su
          map V invert

          cmd online-share $${getExe curl} -F"file=@$f" https://0x0.st | ${open}

          map W online-share

          map [
          map \"
          map \$ push :$
          map \'
          map ]
          map ` !true
          map a :rename

          cmd bulkrename ''${{
            export VIMV=1; ${getExe' pkgs.vimv-rs "vimv"} -- $fs

            ${getExe pkgs.lf} -remote "send $id load"
            ${getExe pkgs.lf} -remote "send $id unselect"
          }}

          map b bulkrename
          map c push A<c-u>
          map d

          cmd edit ''${{
            if [[ ''${NVIM:-} ]]; then
              ${getExe pkgs.lf} -remote "send $id open"
            else
              $EDITOR $f
            fi
          }}

          map e edit
          map f find
          map g/ cd /
          map gD cd ${home}/downloads

          cmd follow_link %{{
            ${getExe pkgs.lf} -remote "send $id select '$(readlink $f)'"
          }}

          map gL follow_link
          map gN cd /nix/store
          map gP cd ${home}/pictures
          map gR cd /run/user/${toString uid}
          map ga cd /usr/share/applications
          map gb cd ${home}/.local/bin
          map gc cd ${home}/.config
          map gd cd  ${home}/documents
          map ge cd ${config.me.flakeDir}
          map gg top
          map gl cd ${home}/.local
          map gm cd /run/media/${user}
          map gn cd /run/current-system/
          map gp cd ${home}/perso
          map gr cd ${home}/repos
          map gt cd ${home}/.local/share/Trash/files
          map gu cd ${home}/uni
          map gv cd ${home}/pictures/videos
          map h updir
          map j down
          map k up

          cmd open &{{
           files="''${fv:-"$fx"}"
           ${open} $files > /dev/null 2>&1
          }}

          map l open
          map m

          cmd mkdir %{{
            printf "Directory name: "
            read newd
            if [[ -z $newd ]]; then
              ${getExe pkgs.lf} -remote "send $id reload"
              return;
            fi

            mkdir -p "$newd"
            ${getExe pkgs.lf} -remote "send $id select \"$newd\""
          }}

          map md mkdir

          cmd edit-new %{{
            printf "File name: "
            read newf
            if [[ -z $newf ]]; then
              ${getExe pkgs.lf} -remote "send $id reload"
              return;
            fi

            ${getExe pkgs.lf} -remote "send $id \$touch \"$newf\""
            ${getExe pkgs.lf} -remote "send $id $\$EDITOR \"$newf\""
          }}

          map me edit-new

          cmd touch %{{
            printf "File name: "
            read newf
            if [[ -z $newf ]]; then
              ${getExe pkgs.lf} -remote "send $id reload"
              return;
            fi

            touch "$newf"
            ${getExe pkgs.lf} -remote "send $id select \"$newf\""
          }}

          map mf touch
          map n search-next
          map p :paste; clear
          map q quit
          map r
          map s visual
          map t

          cmd calc-all-dirsize ''${{
              ${getExe pkgs.lf} -remote "send $id invert"
              ${getExe pkgs.lf} -remote "send $id calcdirsize"
              ${getExe pkgs.lf} -remote "send $id unselect"
              ${getExe pkgs.lf} -remote "send $id show-size"
            }}

          map ta calc-all-dirsize
          map tc :calcdirsize; show-size
          map tn :set sortby natural; set info; set noreverse

          cmd show-size :set sortby size; set info size; set reverse

          map ts show-size
          map tt :set sortby time; set info time; set noreverse
          map u unselect
          map v toggle

          cmd local-share ''${{
            source ~/.config/zsh/widgets.zsh
            out=$(ks $fx)
            device=$(echo "$out" | head -n 1 | cut -d\  -f3)
            count=$(echo "$out" | tail -n +2 | wc -l)

            ${getExe pkgs.lf} -remote 'send unselect'
            ${getExe pkgs.lf} -remote "send echo '$count Files sent to $device'"
          }}

          map w local-share
          map x cut
          map y copy
          map za

          cmd compress %{{
            default_name="$(basename $(echo "$fx" | head -n1))"
            default_name="''${default_name%%.*}.zip"
            
            printf "Archive name (default: $default_name): "
            read new_name
            if [[ -z $new_name ]]; then
              new_name=$default_name
            fi

            ${getExe pkgs.ouch} compress $(realpath --relative-to="$(pwd)" $fx) $new_name 

            ${getExe pkgs.lf} -remote "send $id unselect"
            ${getExe pkgs.lf} -remote "send $id select \"$new_name\""
          }}

          map zc compress

          cmd extract ''${{
            set -f
            ${getExe pkgs.ouch} decompress $fx
            rm $f
          }}

          map ze extract
          map zh
          map zn
          map zr
          map zs
          map zt
          map ~ cd ${home}

          setlocal ~/photos/ info time
          setlocal ~/photos/ sortby time
          setlocal ~/photos/ reverse
          setlocal ~/pictures/ info time
          setlocal ~/pictures/ sortby time
          setlocal ~/pictures/ reverse

          on-focus-gained

          cmd visual-toggle &{{
            while read -r file; do
              lf -remote "send $id toggle \"$file\""
            done <<< "$fv"
            lf -remote "send $id visual-discard"

            if [ -n "$1" ]; then
              lf -remote "send $id push $1"
            fi
          }}

          vmap s visual-toggle
          vmap o visual-change
          vmap <esc> visual-discard

          ${no-confirm [
            "D"
            "x"
            "y"
            "Y"
            "H"
            "l"
            "ze"
            "zc"
            "w"
            "<c-n>"
          ]}

          &[ "$LF_LEVEL" -eq 1 ] || ${getExe pkgs.lf} -remote "send $id echoerr \"Warning: You're in a nested lf instance!\""
        '';

      hj.xdg.config.files."lf/colors".text = builtins.readFile ./colors;
    };

  flake.modules.generic.desktop =
    {
      lib,
      config,
      pkgs,
      ...
    }:
    {
      hj.xdg.config.files."lf/lfrc".text =
        let
          inherit (lib) getExe;
        in
        # bash
        ''
          cmd external-copy ''${{
            if [[ $(uname) == "Darwin" ]]; then
                osascript -e "set theFileList to {}" \
                          $(printf " -e 'set end of theFileList to (POSIX file \"%s\") as alias'" $fx) \
                          -e "set the clipboard to theFileList"
            else
              echo -en "$fx" | sed 's|^|file://|' | tr ' ' '\n' | ${config.me.desktop.copy} --type text/uri-list
            fi
            ${getExe pkgs.lf} -remote 'send unselect'
            ${getExe pkgs.lf} -remote 'send echo "Files copied to clipboard"'
          }}
          map Y external-copy

          cmd copy-path ''${{
            echo -en "$fx" | tr ' ' '\n' | ${config.me.desktop.copy}
            ${getExe pkgs.lf} -remote 'send unselect'
            ${getExe pkgs.lf} -remote 'send echo "Path copied to clipboard"'
          }}
          map H copy-path
        '';
    };

  flake.modules.nixos.desktop =
    { lib, pkgs, ... }:
    {
      tinted.files.".config/mango/config.conf".value = {
        bind = [
          "SUPER,e,toggle_named_scratchpad,foot-lf,none,footclient --app-id foot-lf -e ${lib.getExe pkgs.lf}"
        ];
        window_rule = [ "is_named_scratchpad:1,width:1280,height:800,app_id:foot-lf" ];
      };

      packages = with pkgs; [ libreoffice ];

      xdg.mimeApps.defaultApplications = self.lib.mapMimeEntries [
        "inode/directory"
        "application/x-directory"
      ] "lf";
    };
}
