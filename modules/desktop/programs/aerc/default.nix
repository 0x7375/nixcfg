{
  flake.modules.nixos.desktop =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    {
      packages = with pkgs; [
        aerc
        w3m
      ];

      xdg.desktopEntries.aerc = {
        name = "aerc";
        type = "Application";
        exec = ''sh -c "tmux new-session -d -s aerc aerc; tmux set-option -t aerc status off; tmux set-option -t aerc detach-on-destroy on; tmux attach-session -t aerc"'';
        comment = "Launches the aerc email client";
        terminal = true;
        icon = "utilities-terminal";
        categories = [ "Email" ];
      };

      sops.secrets.full_name.owner = config.me.user;
      sops.secrets.uni_email.owner = config.me.user;
      sops.secrets.uni_username.owner = config.me.user;
      sops.secrets.uni_pw.owner = config.me.user;

      sops.templates."aerc-accounts.conf" = {
        owner = config.me.user;
        path = "${config.me.home}/.config/aerc/accounts.conf";
        mode = "0600";

        content =
          let
            inherit (config.me.host.securityKey) name;
            decryptCmd = "${pkgs.my.fido2-decrypt} ${config.me.host.securityKey.prfPath} ${./aerc_pw_${name}.age}";
            uniPasswordCmd = "${pkgs.coreutils}/bin/cat ${config.sops.secrets.uni_pw.path}";
          in
          # ini
          ''
            [Personal]
            source              = imap://ayko%40posteo.com@posteo.de:143
            source-cred-cmd     = ${decryptCmd}
            outgoing            = smtp://ayko%40posteo.com@posteo.de:587
            outgoing-cred-cmd   = ${decryptCmd}
            default             = INBOX
            from                = Ayko <ayko@posteo.com>
            cache-headers       = true
            copy-to             = Sent
            folders-exclude     = Notes

            [Unicaen]
            source              = imaps://${config.sops.placeholder.uni_username}@webmail.unicaen.fr:993
            source-cred-cmd     = ${uniPasswordCmd}
            outgoing            = smtps+plain://${config.sops.placeholder.uni_username}@smtp.unicaen.fr:465
            outgoing-cred-cmd   = ${uniPasswordCmd}
            default             = INBOX
            from                = ${config.sops.placeholder.full_name} <${config.sops.placeholder.uni_email}>
            cache-headers       = true
            copy-to             = Sent
          '';
      };

      hj.xdg.config.files."aerc/aerc.conf".text =
        # ini
        ''
          [ui]
          mouse-enabled=true
          completion-delay=50ms
          new-message-bell = false

          [filters]
          text/plain=colorize
          text/calendar=calendar
          message/delivery-status=colorize
          message/rfc822=colorize
          # text/html=! html
          text/html=! w3m -T text/html -I UTF-8

          .headers=colorize

          [hooks]
          mail-received=${pkgs.writeShellScript "notify-new" ''
            ACTIVE_WINDOW=$(${lib.getExe' pkgs.mango "mmsg"} get all-monitors | jq -r '.monitors[] | select(.active == true) | .active_client.title')

            [[ "$ACTIVE_WINDOW" != "aerc" ]] && {
              ${lib.getExe pkgs.my.notify} -i mail "New mail from $AERC_FROM_NAME" "$AERC_SUBJECT"
            }

            true
          ''}
        '';

      hj.xdg.config.files."w3m/config".text = ''
        extbrowser xdg-open %s
      '';

      hj.xdg.config.files."w3m/keymap".text = ''
        keymap o EXTERN_LINK
      '';

      hj.xdg.config.files."aerc/binds.conf".text =
        # ini
        ''
          <C-p> = :prev-tab<Enter>
          <C-PgUp> = :prev-tab<Enter>
          <C-n> = :next-tab<Enter>
          <C-PgDn> = :next-tab<Enter>
          \[t = :prev-tab<Enter>
          \]t = :next-tab<Enter>
          <C-t> = :term<Enter>
          ? = :help keys<Enter>
          <C-c> = :quit<Enter>
          <C-q> = :quit<Enter>
          <C-z> = :suspend<Enter>

          [messages]
          <C-h> = :cf -a Personal INBOX<Enter>
          <C-l> = :cf -a Unicaen INBOX<Enter>

          q = :quit<Enter>

          j = :next<Enter>
          <Down> = :next<Enter>
          <C-d> = :next 50%<Enter>
          <C-f> = :next 100%<Enter>
          <PgDn> = :next 100%<Enter>

          k = :prev<Enter>
          <Up> = :prev<Enter>
          <C-u> = :prev 50%<Enter>
          <C-b> = :prev 100%<Enter>
          <PgUp> = :prev 100%<Enter>
          g = :select 0<Enter>
          G = :select -1<Enter>

          J = :next-folder<Enter>
          <C-Down> = :next-folder<Enter>
          K = :prev-folder<Enter>
          <C-Up> = :prev-folder<Enter>
          H = :collapse-folder<Enter>
          <C-Left> = :collapse-folder<Enter>
          L = :expand-folder<Enter>
          <C-Right> = :expand-folder<Enter>

          v = :mark -t<Enter>
          <Space> = :mark -t<Enter>:next<Enter>
          V = :mark -v<Enter>

          T = :toggle-threads<Enter>
          zc = :fold<Enter>
          zo = :unfold<Enter>
          za = :fold -t<Enter>
          zM = :fold -a<Enter>
          zR = :unfold -a<Enter>
          <tab> = :fold -t<Enter>

          zz = :align center<Enter>
          zt = :align top<Enter>
          zb = :align bottom<Enter>

          <Enter> = :view<Enter>
          d = :choose -o y 'Really delete this message' delete-message<Enter>
          D = :mv Trash<Enter>
          a = :archive flat<Enter>
          A = :unmark -a<Enter>:mark -T<Enter>:archive flat<Enter>

          C = :compose<Enter>
          m = :compose<Enter>

          rr = :reply -a<Enter>
          rq = :reply -aq<Enter>
          Rr = :reply<Enter>
          Rq = :reply -q<Enter>

          c = :cf<space>
          $ = :term<space>
          ! = :term<space>
          | = :pipe<space>

          / = :search<space>
          \ = :filter<space>
          n = :next-result<Enter>
          N = :prev-result<Enter>
          <Esc> = :clear<Enter>

          s = :split<Enter>
          S = :vsplit<Enter>

          pl = :patch list<Enter>
          pa = :patch apply <Tab>
          pd = :patch drop <Tab>
          pb = :patch rebase<Enter>
          pt = :patch term<Enter>
          ps = :patch switch <Tab>

          [messages:folder=Drafts]
          <Enter> = :recall<Enter>

          [view]
          / = :toggle-key-passthrough<Enter>/
          q = :close<Enter>
          O = :open<Enter>
          S = :save<space>
          | = :pipe<space>
          D = :delete<Enter>
          A = :archive flat<Enter>

          <C-y> = :copy-link <space>
          <C-l> = :open-link <space>

          f = :forward<Enter>
          rr = :reply -a<Enter>
          rq = :reply -aq<Enter>
          Rr = :reply<Enter>
          Rq = :reply -q<Enter>

          H = :toggle-headers<Enter>
          <C-k> = :prev-part<Enter>
          <C-Up> = :prev-part<Enter>
          <C-j> = :next-part<Enter>
          <C-Down> = :next-part<Enter>
          J = :next<Enter>
          <C-Right> = :next<Enter>
          K = :prev<Enter>
          <C-Left> = :prev<Enter>

          [view::passthrough]
          $noinherit = true
          $ex = <C-x>
          <Esc> = :toggle-key-passthrough<Enter>

          [compose]
          # Keybindings used when the embedded terminal is not selected in the compose
          # view
          $noinherit = true
          $ex = <C-x>
          $complete = <C-o>
          <C-k> = :prev-field<Enter>
          <C-Up> = :prev-field<Enter>
          <C-j> = :next-field<Enter>
          <C-Down> = :next-field<Enter>
          <A-p> = :switch-account -p<Enter>
          <C-Left> = :switch-account -p<Enter>
          <A-n> = :switch-account -n<Enter>
          <C-Right> = :switch-account -n<Enter>
          <tab> = :next-field<Enter>
          <backtab> = :prev-field<Enter>
          <C-p> = :prev-tab<Enter>
          <C-PgUp> = :prev-tab<Enter>
          <C-n> = :next-tab<Enter>
          <C-PgDn> = :next-tab<Enter>

          [compose::editor]
          # Keybindings used when the embedded terminal is selected in the compose view
          $noinherit = true
          $ex = <C-x>
          <C-k> = :prev-field<Enter>
          <C-Up> = :prev-field<Enter>
          <C-j> = :next-field<Enter>
          <C-Down> = :next-field<Enter>
          <C-p> = :prev-tab<Enter>
          <C-PgUp> = :prev-tab<Enter>
          <C-n> = :next-tab<Enter>
          <C-PgDn> = :next-tab<Enter>

          [compose::review]
          # Keybindings used when reviewing a message to be sent
          # Inline comments are used as descriptions on the review screen
          y = :send<Enter> # Send
          n = :abort<Enter> # Abort (discard message, no confirmation)
          s = :sign<Enter> # Toggle signing
          x = :encrypt<Enter> # Toggle encryption to all recipients
          v = :preview<Enter> # Preview message
          p = :postpone<Enter> # Postpone
          q = :choose -o d discard abort -o p postpone postpone<Enter> # Abort or postpone
          e = :edit<Enter> # Edit (body and headers)
          a = :attach<space> # Add attachment
          d = :detach<space> # Remove attachment

          [terminal]
          $noinherit = true
          $ex = <C-x>

          <C-p> = :prev-tab<Enter>
          <C-n> = :next-tab<Enter>
          <C-PgUp> = :prev-tab<Enter>
          <C-PgDn> = :next-tab<Enter>
        '';
    };
}
