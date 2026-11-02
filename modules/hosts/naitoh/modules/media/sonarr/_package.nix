{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  buildDotnetModule,
  dotnetCorePackages,
  sqlite,
  withFFmpeg ? true, # replace bundled ffprobe binary with symlink to ffmpeg package.
  servarr-ffmpeg,
  fetchYarnDeps,
  yarn,
  fixup-yarn-lock,
  nodejs,
  writers,
  prefetch-yarn-deps,
}:
let
  version = "5.0.0.2870";
  src = fetchFromGitHub {
    owner = "Sonarr";
    repo = "Sonarr";
    tag = "v${version}";
    hash = "sha256-Ly6V/go7GCPWBBXpLW6PWUrripFIpDyc72IxoeAHnb8=";
  };
  rid = dotnetCorePackages.systemToDotnetRid stdenvNoCC.hostPlatform.system;
in
buildDotnetModule {
  pname = "sonarr";
  inherit version src;

  postPatch = ''
    mv src/NuGet.Config NuGet.Config
    rm global.json
  '';

  # Upstream expects to be ran from a "bin" directory
  installPath = "${placeholder "out"}/lib/sonarr/bin";
  strictDeps = true;
  nativeBuildInputs = [
    nodejs
    yarn
    prefetch-yarn-deps
    fixup-yarn-lock
  ];

  yarnOfflineCache = fetchYarnDeps {
    yarnLock = "${src}/yarn.lock";
    hash = "sha256-nbXSMPS02jGSJpzBpG+yhatIQGB1s8QS3JWARn3RO5U=";
  };

  ffprobe = lib.optionalDrvAttr withFFmpeg (lib.getExe' servarr-ffmpeg "ffprobe");

  postConfigure = ''
    yarn config --offline set yarn-offline-mirror "$yarnOfflineCache"
    fixup-yarn-lock yarn.lock
    yarn install --offline --frozen-lockfile --ignore-platform --ignore-scripts --no-progress --non-interactive
    patchShebangs --build node_modules
  '';
  postBuild = ''
    yarn --offline run build
  '';
  postInstall =
    let
      packageInfo = writers.writeText "package_info" ''
        PackageVersion=${version}
        PackageAuthor=[NixOS](https://nixos.org)
      '';
    in
    lib.optionalString withFFmpeg ''
      ln -sf -- "$ffprobe" "$out/lib/sonarr/bin/ffprobe"
    ''
    + ''
      cp -a -- _output/UI "$out/lib/sonarr/bin/UI"
      ln -s ${packageInfo} $out/lib/sonarr/package_info
    '';
  # Add an alias for compatibility with Sonarr v3 package.
  postFixup = ''
    ln -s -- Sonarr "$out/bin/NzbDrone"
  '';

  nugetDeps = ./deps.json;

  runtimeDeps = [ sqlite ];

  dotnet-sdk = dotnetCorePackages.sdk_10_0;
  dotnet-runtime = dotnetCorePackages.aspnetcore_10_0;

  doCheck = false; # turn back on once it builds

  __darwinAllowLocalNetworking = true; # for tests

  __structuredAttrs = true; # for Copyright property that contains spaces

  executables = [ "Sonarr" ];

  projectFile = [
    "src/NzbDrone.Console/Sonarr.Console.csproj"
    "src/NzbDrone.Mono/Sonarr.Mono.csproj"
  ];

  testProjectFile = [
    "src/NzbDrone.Api.Test/Sonarr.Api.Test.csproj"
    "src/NzbDrone.Common.Test/Sonarr.Common.Test.csproj"
    "src/NzbDrone.Core.Test/Sonarr.Core.Test.csproj"
    "src/NzbDrone.Host.Test/Sonarr.Host.Test.csproj"
    "src/NzbDrone.Libraries.Test/Sonarr.Libraries.Test.csproj"
    "src/NzbDrone.Mono.Test/Sonarr.Mono.Test.csproj"
    "src/NzbDrone.Test.Common/Sonarr.Test.Common.csproj"
  ];

  # https://github.com/NixOS/nixpkgs/pull/491217
  dotnetTestFlags = lib.optionals stdenvNoCC.buildPlatform.isDarwin [
    "--environment:DOTNET_SYSTEM_NET_DISABLEIPV6=1"
  ];

  dotnetFlags = [
    "--property:TargetFramework=net10.0"
    "--property:EnableAnalyzers=false"
    "--property:SentryUploadSymbols=false" # Fix Sentry upload failed warnings
    # Override defaults in src/Directory.Build.props that use current time.
    "--property:Copyright=Copyright 2014-2026 sonarr.tv (GNU General Public v3)"
    "--property:AssemblyVersion=${version}"
    "--property:AssemblyConfiguration=main"
    "--property:RuntimeIdentifier=${rid}"
  ];

  # Skip manual, integration, automation and platform-dependent tests.
  testFilters = [
    "TestCategory!=ManualTest"
    "TestCategory!=IntegrationTest"
    "TestCategory!=AutomationTest"

    # makes real HTTP requests
    "FullyQualifiedName!~NzbDrone.Core.Test.UpdateTests.UpdatePackageProviderFixture"
    "FullyQualifiedName!~NzbDrone.Core.Test.TvTests.RefreshEpisodeServiceFixture"
  ]
  ++ lib.optionals stdenvNoCC.buildPlatform.isDarwin [
    # fails on macOS
    "FullyQualifiedName!~NzbDrone.Core.Test.Http.HttpProxySettingsProviderFixture"
  ];

  disabledTests = [
    # setgid tests
    "NzbDrone.Mono.Test.DiskProviderTests.DiskProviderFixture.should_preserve_setgid_on_set_folder_permissions"
    "NzbDrone.Mono.Test.DiskProviderTests.DiskProviderFixture.should_clear_setgid_on_set_folder_permissions"

    # we do not set application data directory during tests (i.e. XDG data directory)
    "NzbDrone.Mono.Test.DiskProviderTests.FreeSpaceFixture.should_return_free_disk_space"
    "NzbDrone.Common.Test.ServiceFactoryFixture.event_handlers_should_be_unique"

    # attempts to read /etc/*release and fails since it does not exist
    "NzbDrone.Mono.Test.EnvironmentInfo.ReleaseFileVersionAdapterFixture.should_get_version_info"

    # fails to start test dummy because it cannot locate .NET runtime for some reason
    "NzbDrone.Common.Test.ProcessProviderFixture.Should_be_able_to_start_process"
    "NzbDrone.Common.Test.ProcessProviderFixture.kill_all_should_kill_all_process_with_name"
  ];

  meta = {
    description = "Smart PVR for newsgroup and bittorrent users";
    homepage = "https://sonarr.tv";
    license = lib.licenses.gpl3Only;
    maintainers = with lib.maintainers; [
      purcell
      tie
      niklaskorz
      karaolidis
      nyanloutre
    ];
    mainProgram = "Sonarr";
    # platforms inherited from dotnet-sdk.
  };
}
