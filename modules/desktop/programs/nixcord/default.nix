{
  # TODO: darwin fails to build
  flake.modules.nixos.desktop =
    { config, ... }:
    {
      persistUser.directories = [
        ".config/vesktop"
        ".config/Vencord"
      ];

      me.desktop.assign = [
        {
          type = "appid";
          name = "vesktop";
          workspace = "4";
        }
      ];

      unfree-packages = [ "discord" ];

      programs.nixcord = {
        enable = true;
        discord = {
          openASAR.enable = false;
          vencord.enable = true;
        };
        inherit (config.me) user;
        config.plugins = {
          fixCodeblockGap.enable = true;
          ircColors.enable = true;
          hideMedia.enable = true;
          fakeNitro.enable = true;
          alwaysTrust.enable = true;
          betterSettings.enable = true;
          clearUrls.enable = true;
          expressionCloner.enable = true;
          crashHandler.enable = true;
          noOnboardingDelay.enable = true;
          noReplyMention.enable = true;
          silentTyping.enable = true;
          noTypingAnimation.enable = true;
          previewMessage.enable = true;
          webScreenShareFixes.enable = true;
          youtubeAdblock.enable = true;
        };
      };
    };
}
