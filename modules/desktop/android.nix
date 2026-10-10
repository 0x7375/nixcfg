{
  flake.modules.nixos.desktop =
    {
      pkgs,
      config,
      ...
    }:
    {
      persistUser.directories = [
        ".android"
        ".local/share/android"
      ];

      users.users.${config.me.user}.extraGroups = [ "adbusers" ];

      unfree-packages = [ "android-studio-stable" ];

      packages = with pkgs; [
        android-tools
        # android-studio
        scrcpy
      ];
    };
}
