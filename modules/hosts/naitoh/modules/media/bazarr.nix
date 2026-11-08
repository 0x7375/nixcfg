{
  flake.modules.nixos.naitoh =
    { config, mv, ... }:
    {
      me.services.bazarr = {
        subdomain = "subtitles";
        port = config.services.bazarr.listenPort;
      };

      services.bazarr = {
        enable = true;
        package = mv.tip.bazarr;
        openFirewall = true;
        group = config.me.mediaGroup;
        dataDir = "/data/main/.state/bazarr";
      };

      systemd.services.bazarr.serviceConfig.UMask = "0002";
    };
}
