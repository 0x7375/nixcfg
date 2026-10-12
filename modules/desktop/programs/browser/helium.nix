let
  extensions = {
    ublock = "cjpalhdlnbpafiamejdnhcphjbkeiagm";
    kagiTranslate = "alblebhaoakdgapamjdifdfnaicpnklm";
    stylus = "clngdbkpkpeebahjckkjfobafhncgmne";
    vimium = "dbepggeogbaibhgnhhndojpepiihcmeb";
    bitwarden = "nngceckbapebfimnlniiiahkandclblb";
    removeYoutubeSuggestions = "cdhdichomdnlaadbndgmagohccgpejae";
    sponsorBlock = "mnjggcdmjocbbbhaepdhchncahnbgone";
    deArrow = "enamippconapkdmgfgjchkhakpfinmaj";
    detachTab = "jalaajddhemiiilfhmenogfbpkbgglkk";
    captchaBuster = "mpbjkejclgfgadiemmefgebjfooflfhl";
    _7tv = "ammjkodgmmoknidbanneddgankgfejfh";
  };

  policies =
    lib:
    let
      mkDisabledPermissions = perms: lib.genAttrs (map (p: "Default${p}Setting") perms) (_: 2);
    in
    {
      DefaultSearchProviderEnabled = true;
      DefaultSearchProviderName = "Google";
      DefaultSearchProviderSearchURL = "https://www.google.com/search?q={searchTerms}";
      DefaultSearchProviderIconURL = "https://google.com//favicon.ico";
      DefaultSearchProviderNewTabURL = "https://google.com/";

      DefaultCookiesSetting = 4;

      CookiesAllowedForUrls = [
        "https://reddit.com"
        "https://twitch.tv"
        "https://monkeytype.com"
        "https://youtube.com"
        "https://discord.com"
        "https://keybr.com"
        "https://discord.com"
        "https://claude.ai"
        "https://gemini.google.com"
      ];
      ClearBrowsingDataOnExitList = [
        "cached_images_and_files"
        "download_history"
      ];

      SearchSuggestEnabled = false;

      AutofillAddressEnabled = false;
      AutofillCreditCardEnabled = false;

      DnsOverHttpsMode = "off";
      BlockThirdPartyCookies = true;
      HttpsOnlyMode = "force_enabled";
      SSLErrorOverrideAllowed = false;
      MetricsReportingEnabled = false;
      SafeBrowsingExtendedReportingEnabled = false;
      UrlKeyedAnonymizedDataCollectionEnabled = false;

      BackgroundModeEnabled = true;
      SpellCheckServiceEnabled = false;
      NewTabPageLocation = "about:blank";
      RestoreOnStartup = 1;
      AutoplayAllowed = false;

      ExtensionInstallSources = [
        "https://github.com/*"
        "https://raw.githubusercontent.com/*"
        "https://greasyfork.org/*"
        "https://update.greasyfork.org/*"
        "https://clients2.google.com/service/update2/crx"
        "https://chrome.google.com/webstore/*"
        "https://clients2.9oo91e.qjz9zk/service/update2/crx"
      ];

      "3rdparty".extensions = {
        ${extensions.ublock}.adminSettings = builtins.toJSON {
          userSettings = {
            uiAccentCustom = true;
            uiAccentCustom0 = "#98971a";
            cloudStorageEnabled = false;
            importedLists = [ ];
            advancedUserEnabled = true;
            firewallPaneMinimized = false;
          };
          selectedFilterLists = [
            "user-filters"
            "ublock-filters"
            "ublock-badware"
            "ublock-privacy"
            "ublock-quick-fixes"
            "ublock-unbreak"
            "easylist"
            "adguard-generic"
            "adguard-mobile"
            "easyprivacy"
            "adguard-spyware"
            "adguard-spyware-url"
            "block-lan"
            "urlhaus-1"
            "curben-phishing"
            "plowe-0"
            "dpollock-0"
            "fanboy-cookiemonster"
            "ublock-cookies-easylist"
            "adguard-cookies"
            "ublock-cookies-adguard"
            "fanboy-social"
            "adguard-social"
            "fanboy-thirdparty_social"
            "easylist-chat"
            "easylist-newsletters"
            "easylist-notifications"
            "easylist-annoyances"
            "adguard-mobile-app-banners"
            "adguard-other-annoyances"
            "adguard-popup-overlays"
            "adguard-widgets"
            "ublock-annoyances"
            "FRA-0"
          ];
          hiddenSettings = {
            userResourcesLocation = "https://github.com/pixeltris/TwitchAdSolutions/raw/master/vaft/vaft-ublock-origin.js";
          };
          "userFilters" = builtins.readFile ./uBlockFilters.txt;
        };
      };
    }
    // mkDisabledPermissions [
      # "Notifications"
      "Geolocation"
      "Cameras"
      "Microphone"
      "Popups"
    ];
in
{ inputs, ... }: {

  flake.modules.generic.desktop =
    { pkgs, ... }:
    {
      nixpkgs.overlays = [
        (final: prev: {
          helium = inputs.helium.packages.${final.stdenv.hostPlatform.system}.default.overrideAttrs (old: {
            postFixup =
              (old.postFixup or "")
              + (
                let
                  flags = [
                    "--enable-features=HeliumMiddleClickAutoscroll"
                    "--no-first-run"
                    "--remote-debugging-port=9800"
                  ];
                in
                ''
                  wrapProgram $out/bin/helium --add-flags '${builtins.concatStringsSep " " flags}'
                ''
              );
          });
        })
      ];

      packages = [ pkgs.helium ];
    };

  flake.modules.nixos.desktop =
    { lib, ... }:
    {
      persistUser.directories = [
        ".config/net.imput.helium"
        ".cache/net.imput.helium"
      ];

      programs.chromium = {
        enable = true;
        extensions = lib.attrValues extensions;
        extraOpts = policies lib;
      };
    };

  flake.modules.darwin.desktop =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    {
      activation =
        let
          managedPlist = pkgs.writeText "net.imput.helium.plist" (
            lib.generators.toPlist { escape = true; } (policies lib)
          );
        in
        ''
          install -d -m 0755 "/Library/Managed Preferences/${config.me.user}"
          install -m 0644 ${managedPlist} "/Library/Managed Preferences/${config.me.user}/net.imput.helium.plist"
        '';
    };
}
