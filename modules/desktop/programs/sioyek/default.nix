{ self, ... }:

{
  flake.modules.nixos.desktop =
    { pkgs, ... }:
    {
      persistUser.directories = [
        ".local/share/sioyek"
      ];

      packages = with pkgs; [ my.zaread ];

      xdg.mimeApps.defaultApplications = {
        "application/pdf" = "sioyek.desktop";
      }
      // (self.lib.mapMimeEntries [
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        "application/msword"
        "application/vnd.ms-excel"
        "application/vnd.ms-powerpoint"
        "application/vnd.oasis.opendocument.text"
        "application/vnd.oasis.opendocument.spreadsheet"
        "application/vnd.oasis.opendocument.presentation"
        "text/rtf"
        "text/csv"
      ] "zaread");

      xdg.desktopEntries.zaread = {
        name = "Zaread";
        exec = "zaread %F";
        terminal = false;
        categories = [
          "Office"
          "Viewer"
        ];
      };
    };

  flake.modules.generic.desktop =
    { pkgs, ... }:
    {
      packages = [
        (pkgs.sioyek.overrideAttrs (old: {
          version = "2.0.0-unstable-2026-11-04";

          src = pkgs.fetchFromGitHub {
            owner = "ahrm";
            repo = "sioyek";
            rev = "1e2f8037353724a83ccb10a697e28e295383e017";
            hash = "sha256-wfV4Mwpj1WE00UMTE+8OzVTf3IwF5+ReM4NlBbsy5Ec=";
          };

          patches = (old.patches or [ ]) ++ [
            ./fit_page_height_ignore_statusbar.patch
            # fixes: https://github.com/ahrm/sioyek/issues/1283#issuecomment-4469874080
            ./remove_qsuface_format.patch
          ];
        }))
      ];

      tinted.files.".config/sioyek/prefs_user.config".text =
        p:
        # sway
        ''
          startup_commands toggle_status_bar;toggle_titlebar
          status_bar_color             ${p.bg0}
          status_bar_text_color        ${p.fg0}

          ui_text_color                ${p.fg0}
          ui_background_color          ${p.bg0}
          ui_selected_background_color ${p.fg0}
          ui_selected_text_color       ${p.bg0}

          text_highlight_color         ${p.orange}
          search_highlight_color       ${p.blue}
          link_highlight_color         ${p.blue}

          custom_background_color      ${p.bg0}
          custom_text_color            ${p.fg0}

          should_launch_new_window 1
          page_separator_width 1
          scroll_past_document_ends 0
          show_statusbar_only_when_hovered 1
        '';

      hj.xdg.config.files."sioyek/keys_user.config".text =
        # sway
        ''
          close_window q

          move_down_smooth j
          move_up_smooth k
          move_left l
          move_right h

          goto_beginning go

          next_page <C-j>
          previous_page <C-k>
          next_page <right>
          previous_page <left>
          next_page f
          previous_page b
          previous_page <f9>
          next_page <f10>

          screen_down d
          screen_up u

          add_highlight_with_current_type H
          delete_highlight D

          fit_to_page_width s
          fit_to_page_height a

          zoom_out J
          zoom_in K
          toggle_custom_color i
          rotate_clockwise <C-r>
          reload r

          new_window <C-n>

          goto_toc t
        '';
    };
}
