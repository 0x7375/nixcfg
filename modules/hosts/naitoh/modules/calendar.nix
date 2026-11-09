{
  flake.modules.nixos.naitoh =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      inherit (config.me.services.radicale) port;

      notesUser = config.services.syncthing.user;
      notesDir = "/data/main/syncthing/notes";

      radicaleUser = "admin";

      emacs = (pkgs.emacsPackagesFor pkgs.emacs-nox).emacsWithPackages (epkgs: [
        epkgs.melpaStablePackages.org-caldav
      ]);

      emacsConfig =
        pkgs.writeText "org-caldav.el"
          # lisp
          ''
            (require 'org-caldav)

            (require 'org-agenda)

            ;; Work around org-caldav deleting entire subtrees when skipping
            ;; headings without timestamps. Preserve timestamped descendants.
            (defun org-caldav-skip-function (backend)
              "Skip entries without timestamps without removing their descendants."
              (org-caldav-debug-print 2 "Skipping over excluded entries")
              (when (eq backend 'icalendar)
                (org-map-entries
                 (lambda ()
                   (let ((skip
                          (save-excursion
                            (apply #'org-agenda-skip-entry-if
                                   org-caldav-skip-conditions)))
                         (days-in-past
                          (when org-caldav-days-in-past
                            (- (abs org-caldav-days-in-past))))
                         (stamp
                          (or (org-entry-get nil "TIMESTAMP" t)
                              (org-entry-get nil "CLOSED" t))))
                     (when (or skip
                               (and stamp days-in-past
                                    (> days-in-past
                                       (org-time-stamp-to-now stamp))))
                       ;; Remove only this heading's own section, not its children.
                       (delete-region (point) (org-entry-end-position))
                       (setq org-map-continue-from (point)))))))
              (org-caldav-debug-print 2 "Finished skipping"))

            (require 'auth-source)

            (setq org-caldav-url
                  "http://127.0.0.1:${toString port}/${radicaleUser}")
            (setq org-caldav-calendar-id "d1672171-cb7c-4533-d8f2-0e5ca9ca4c69")

            (setq org-caldav-sync-direction 'org->cal)
            (setq org-caldav-inbox nil)

            (setq org-caldav-files
                  (directory-files "${notesDir}" t "\\.org\\'"))

            (setq org-icalendar-timezone "Europe/Paris")
            (setq org-caldav-save-directory "/var/lib/org-caldav")

            (require 'org-id)
            (setq org-id-locations-file
                  "/var/lib/org-caldav/.org-id-locations")

            (setq org-caldav-delete-calendar-entries 'always)
            (setq org-caldav-skip-conditions '(nottimestamp))
            (setq org-export-with-broken-links t)
            (setq org-caldav-resume-aborted 'always)
            (setq org-icalendar-use-scheduled
             '(todo-start event-if-not-todo event-if-todo-not-done))

            (setq auth-sources
                  '("${config.sops.templates.calendar_orgzly_auth.path}"))

            (setq make-backup-files nil)
          '';

      sync = pkgs.writeShellScript "org-caldav-sync" ''
        exec ${lib.getExe emacs} \
          --batch \
          -Q \
          --load ${emacsConfig} \
          --eval '(org-caldav-sync)'
      '';

      watcher = pkgs.writeShellScript "org-caldav-watcher" ''
        exec ${lib.getExe pkgs.watchexec} \
          --shell=none \
          --watch-non-recursive ${lib.escapeShellArg notesDir} \
          --exts org \
          --debounce 3s \
          -- ${sync}
      '';
    in
    {
      me.hostSecrets.radicale_users.owner = "radicale";
      sops.secrets.calendar_default_pw.owner = notesUser;
      sops.templates.calendar_orgzly_auth = {
        owner = notesUser;
        mode = "0400";
        content = ''
          machine 127.0.0.1:${toString port} port http login ${radicaleUser} password ${config.sops.placeholder.calendar_default_pw}
        '';
      };

      persist.directories = [ "/var/lib/org-caldav" ];

      services.radicale = {
        enable = true;
        settings = {
          server.hosts = [ "0.0.0.0:${toString port}" ];
          auth = {
            type = "htpasswd";
            htpasswd_filename = config.sops.secrets.radicale_users.path;
            htpasswd_encryption = "bcrypt";
          };
        };
      };

      systemd.services.org-caldav-publish = {
        description = "Publish Org notes to Radicale";
        wantedBy = [ "multi-user.target" ];
        after = [
          "radicale.service"
          "syncthing.service"
        ];
        requires = [ "radicale.service" ];

        serviceConfig = {
          User = notesUser;
          WorkingDirectory = notesDir;

          StateDirectory = "org-caldav";
          Environment = [ "HOME=/var/lib/org-caldav" ];

          ExecStart = watcher;

          Restart = "always";
          RestartSec = "2s";
        };
      };
    };
}
