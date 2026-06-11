# Builds a single standalone Dart SDK package from one data/dart.json entry.
#
# Dart is self-contained: it never downloads binaries at runtime, so on Linux a
# plain autoPatchelf is enough. On Darwin the prebuilt arm64 binaries run as-is.
{ pkgs, lib, entry }:

let
  inherit (entry) version channel url sha256;
  isLinux = pkgs.stdenv.hostPlatform.isLinux;
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "dart";
  inherit version;

  src = pkgs.fetchurl { inherit url sha256; };

  nativeBuildInputs =
    [ pkgs.unzip pkgs.makeWrapper ]
    ++ lib.optionals isLinux [ pkgs.autoPatchelfHook ];

  # Shared libs the Dart VM / AOT runtime link against on Linux.
  buildInputs = lib.optionals isLinux [ pkgs.stdenv.cc.cc.lib pkgs.zlib ];

  # Stay in the build root so the extracted `dart-sdk/` dir is addressable.
  sourceRoot = ".";

  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  # The zip extracts to a top-level `dart-sdk/` directory.
  installPhase = ''
    runHook preInstall
    mkdir -p $out/libexec
    cp -r dart-sdk $out/libexec/dart-sdk
    mkdir -p $out/bin
    # Wrap (not symlink) so the VM resolves its SDK root from the real path.
    for b in dart; do
      makeWrapper $out/libexec/dart-sdk/bin/$b $out/bin/$b
    done
    runHook postInstall
  '';

  passthru = { inherit channel version; };

  meta = {
    description = "Dart SDK ${version} (${channel} channel)";
    homepage = "https://dart.dev";
    license = lib.licenses.bsd3;
    platforms = [ entry.system ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "dart";
  };
}
