p:
# css
''
  /*
  * GTK Colors (GTK4)
  * Copied from Noctalia templates
  */

  @define-color accent_color ${p.green};
  @define-color accent_bg_color ${p.green};
  @define-color accent_fg_color ${p.bg0};

  @define-color destructive_bg_color ${p.red};
  @define-color destructive_fg_color ${p.bg0};

  @define-color error_bg_color ${p.red};
  @define-color error_fg_color ${p.bg0};

  @define-color window_bg_color ${p.bg0_hard};
  @define-color window_fg_color ${p.fg0};

  @define-color view_bg_color ${p.bg0_hard};
  @define-color view_fg_color ${p.fg0};

  @define-color headerbar_bg_color ${p.bg0_hard};
  @define-color headerbar_fg_color ${p.fg0};
  @define-color headerbar_backdrop_color @window_bg_color;

  @define-color popover_bg_color ${p.bg1};
  @define-color popover_fg_color ${p.fg0};

  @define-color card_bg_color ${p.bg1};
  @define-color card_fg_color ${p.fg0};

  @define-color dialog_bg_color ${p.bg0_hard};
  @define-color dialog_fg_color ${p.fg0};

  @define-color overview_bg_color ${p.bg1};
  @define-color overview_fg_color ${p.fg0};

  @define-color sidebar_bg_color ${p.bg1};
  @define-color sidebar_fg_color ${p.fg0};
  @define-color sidebar_backdrop_color @window_bg_color;
  @define-color sidebar_border_color @window_bg_color;

  @define-color secondary_sidebar_bg_color ${p.bg0_hard};
  @define-color secondary_sidebar_fg_color ${p.fg0};

  /* Backdrop/unfocused states */
  @define-color theme_unfocused_fg_color @window_fg_color;
  @define-color theme_unfocused_text_color @view_fg_color;
  @define-color theme_unfocused_bg_color @window_bg_color;
  @define-color theme_unfocused_base_color @window_bg_color;
  @define-color theme_unfocused_selected_bg_color @accent_bg_color;
  @define-color theme_unfocused_selected_fg_color @accent_fg_color;

  toastoverlay > toast {
    background-color: var(--popover-bg-color);
    color: var(--popover-fg-color);
  }

  :root {
    --accent-color: ${p.green};
    --accent-bg-color: ${p.green}; 
    --accent-fg-color: ${p.bg0};

    --destructive-bg-color: ${p.red};
    --destructive-fg-color: ${p.bg0};

    --error-bg-color: ${p.red};
    --error-fg-color: ${p.bg0};
    --error-color: ${p.red};

    --window-bg-color: ${p.bg0_hard};
    --window-fg-color: ${p.fg0};

    --view-bg-color: ${p.bg0_hard};
    --view-fg-color: ${p.fg0};

    --headerbar-bg-color: ${p.bg0_hard};
    --headerbar-fg-color: ${p.fg0};
    --headerbar-backdrop-color: @window_bg_color;

    --popover-bg-color: ${p.bg1};
    --popover-fg-color: ${p.fg0};

    --card-bg-color: ${p.bg1};
    --card-fg-color: ${p.fg0};

    --dialog-bg-color: ${p.bg0_hard};
    --dialog-fg-color: ${p.fg0};

    --overview-bg-color: ${p.bg1};
    --overview-fg-color: ${p.fg0};

    --sidebar-bg-color: ${p.bg1};
    --sidebar-fg-color: ${p.fg0};
    --sidebar-backdrop-color: @window_bg_color;
    --sidebar-border-color: @window_bg_color;

    --warning-bg-color: ${p.blue};
    --warning-fg-color: ${p.bg0};
    --warning-color: ${p.blue};

    --success-color: ${p.yellow};
    --success-bg-color: ${p.yellow};
    --success-fg-color: ${p.bg0};
    
    --shade-color: rgba(0, 0, 0, 0.36);
  }
''
