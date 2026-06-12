# Builds a single Flutter SDK package from one data/flutter.json entry.
#
# Unlike Dart, Flutter's tarball ships an *incomplete* bin/cache: on first run it
# downloads the engine + a bundled Dart SDK into its own directory and then execs
# those freshly-downloaded ELF binaries. That breaks on NixOS two ways — the store
# path is read-only, and the downloaded binaries aren't patched.
#
# So we:
#   * copy the pristine SDK to a writable per-user cache dir on first run, and
#   * (Linux) run everything inside a buildFHSEnv whose /lib provides the standard
#     loader + libraries, so the runtime-downloaded engine binaries resolve their
#     dependencies normally.
# On Darwin no FHS is needed; the prebuilt arm64 artifacts run natively.
{ pkgs, lib, entry, sanitize }:

let
  inherit (entry) version channel url sha256;
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
  attr = sanitize version;

  # Pristine, read-only store copy of the SDK (tarball extracts to `flutter/`).
  sdk = pkgs.stdenvNoCC.mkDerivation {
    pname = "flutter-sdk";
    inherit version;
    src = pkgs.fetchurl { inherit url sha256; };
    sourceRoot = "."; # stay in build root; tarball extracts to `flutter/`
    dontConfigure = true;
    dontBuild = true;
    dontFixup = true; # keep binaries pristine; the FHS env supplies libraries
    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r flutter/. $out/
      runHook postInstall
    '';
  };

  # Body shared by both platforms: materialise a writable copy of the SDK once,
  # point pub/flutter caches outside the store, then run the requested tool.
  # Expects the tool name as $1.
  setupBody = ''
    cache="''${XDG_CACHE_HOME:-$HOME/.cache}/dash-flake"
    home="$cache/flutter-${version}"
    if [ ! -e "$home/.dash-ready" ]; then
      rm -rf "$home"
      mkdir -p "$home"
      cp -r ${sdk}/. "$home/"
      chmod -R u+w "$home"
      touch "$home/.dash-ready"
    fi
    export PUB_CACHE="''${PUB_CACHE:-$cache/pub-cache}"
    export PATH="$home/bin:$PATH"
    tool="$1"; shift
    exec "$home/bin/$tool" "$@"
  '';
in
if isLinux then
  let
    # The full gtk+-3.0 pkg-config closure, captured exactly as nixpkgs' own
    # pkg-config setup hook computes it (transitive deps and all). Baking this
    # into PKG_CONFIG_PATH lets `flutter doctor` and `flutter build linux` find
    # GTK out of the box — consumers don't need to add gtk3/pkg-config/etc. to
    # their devenv. The store paths it points at are readable inside the FHS env.
    pkgConfigPath = pkgs.runCommand "flutter-linux-pkg-config-path"
      {
        nativeBuildInputs = [ pkgs.pkg-config ];
        buildInputs = [ pkgs.gtk3 ];
      }
      ''printf '%s' "$PKG_CONFIG_PATH" > $out'';

    runScript = pkgs.writeShellScript "flutter-run-${attr}" (''
      export PKG_CONFIG_PATH="$(cat ${pkgConfigPath})''${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}"
    '' + setupBody);

    fhs = pkgs.buildFHSEnv {
      name = "flutter-fhs-${attr}";
      # Loader + libraries for Flutter tooling and the runtime-downloaded engine.
      # Library set mirrors nixpkgs' flutter wrapper (Linux desktop target).
      targetPkgs = p: with p; [
        bashInteractive coreutils which gitMinimal curl cacert
        # toolchain for `flutter build linux`
        pkg-config cmake ninja clang
        # engine / desktop runtime libraries
        glib gtk3 atk cairo gdk-pixbuf harfbuzz libepoxy pango
        zlib libdeflate libGL libx11 xorgproto
        stdenv.cc.cc.lib
      ];
      inherit runScript;
    };
  in
  pkgs.runCommand "flutter-${version}"
    {
      nativeBuildInputs = [ pkgs.makeWrapper ];
      passthru = { inherit channel version sdk; };
      meta = {
        description = "Flutter SDK ${version} (${channel} channel)";
        homepage = "https://flutter.dev";
        license = lib.licenses.bsd3;
        platforms = [ entry.system ];
        sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
        mainProgram = "flutter";
      };
    }
    ''
      mkdir -p $out/bin
      makeWrapper ${fhs}/bin/flutter-fhs-${attr} $out/bin/flutter --add-flags flutter
      makeWrapper ${fhs}/bin/flutter-fhs-${attr} $out/bin/dart    --add-flags dart
    ''
else
  # Darwin: no FHS needed; the runner does the writable-copy setup then execs the
  # requested tool (passed as $1, matching setupBody's contract).
  let
    runner = pkgs.writeShellScript "flutter-run-${attr}" setupBody;
  in
  pkgs.runCommand "flutter-${version}"
    {
      nativeBuildInputs = [ pkgs.makeWrapper ];
      passthru = { inherit channel version sdk; };
      meta = {
        description = "Flutter SDK ${version} (${channel} channel)";
        homepage = "https://flutter.dev";
        license = lib.licenses.bsd3;
        platforms = [ entry.system ];
        sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
        mainProgram = "flutter";
      };
    }
    ''
      mkdir -p $out/bin
      makeWrapper ${runner} $out/bin/flutter --add-flags flutter
      makeWrapper ${runner} $out/bin/dart    --add-flags dart
    ''
