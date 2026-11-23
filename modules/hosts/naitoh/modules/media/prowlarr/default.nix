{ self, ... }:

{
  flake.modules.nixos.naitoh =
    {
      lib,
      mv,
      config,
      ...
    }:
    {
      me.services = {
        flaresolverr = {
          subdomain = "solver";
          inherit (config.services.flaresolverr) port;
        };
        prowlarr = {
          subdomain = "indexer";
          inherit (config.nixflix.prowlarr.config.hostConfig) port;
        };
      };

      me.hostSecrets."prowlarr/api_key" = { };
      me.hostSecrets."prowlarr/pw" = { };

      me.hostSecrets."indexers/c411" = { };
      me.hostSecrets."indexers/tr4ker" = { };
      me.hostSecrets."indexers/v3x" = { };
      me.hostSecrets."indexers/rutracker" = { };
      me.hostSecrets."indexers/speedapp" = { };

      networking.enableIPv6 = false;

      systemd.services.prowlarr.preStart =
        let
          trackers = [
            "c411"
            "tr4ker"
            "v3x"
          ];
        in
        # bash
        ''
          DATA_DIR="${config.nixflix.prowlarr.dataDir}"
          mkdir -p "$DATA_DIR/Definitions/Custom"

          ${lib.concatMapStrings (tracker: ''
            cp ${./${tracker}.yml} "$DATA_DIR/Definitions/Custom/${tracker}-custom.yml"
            chmod 644 "$DATA_DIR/Definitions/Custom/${tracker}-custom.yml"
          '') trackers}
        '';

      services.flaresolverr.package = self.lib.withMainProgram "flaresolverr" mv.latest.flaresolverr;

      nixflix = {
        flaresolverr.enable = true;
        prowlarr = {
          enable = true;
          package = self.lib.withMainProgram "Prowlarr" mv.latest.prowlarr;
          openFirewall = true;
          config = {
            apiKey._secret = config.sops.secrets."prowlarr/api_key".path;
            hostConfig.password._secret = config.sops.secrets."prowlarr/pw".path;
            indexers =
              let
                tags = [ "flaresolverr" ];
                withSolver = name: { inherit name tags; };
              in
              [
                { name = "Knaben"; }
                { name = "LimeTorrents"; }
                { name = "Nyaa.si"; }
                { name = "Tokyo Toshokan"; }
                (withSolver "1337x")
                (withSolver "Uindex")
                (withSolver "Torrent Downloads")
                {
                  name = "C411 (Custom)";
                  apikey._secret = config.sops.secrets."indexers/c411".path;
                  priority = 10;
                  multilang = true;
                  multilanguage = 5;
                }
                {
                  name = "TR4KER (Custom)";
                  apikey._secret = config.sops.secrets."indexers/tr4ker".path;
                  priority = 10;
                  multilang = true;
                  multilanguage = 5;
                }
                {
                  name = "V3X (Custom)";
                  apikey._secret = config.sops.secrets."indexers/v3x".path;
                  priority = 10;
                  multilang = true;
                  multilanguage = 5;
                }
                {
                  name = "SpeedApp.io";
                  email = "revenge.spiritual345@0xaa.me";
                  password._secret = config.sops.secrets."indexers/speedapp".path;
                  priority = 15;
                }
                # not until this is merged ig https://github.com/FlareSolverr/FlareSolverr/pull/1809
                # (
                #   (withSolver "RuTracker.org")
                #   // {
                #     username = "seldom511";
                #     password._secret = config.sops.secrets."indexers/rutracker".path;
                #     russianLetters = true;
                #     addRussianToTitle = false;
                #     priority = 20;
                #   }
                # )
              ];
          };
        };
      };
    };
}
