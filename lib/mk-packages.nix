# Builds the full attrset of Dart + Flutter packages for `pkgs`' own system,
# plus channel-latest aliases and a `default`. Shared by `packages.<system>`
# and `overlays.default` so the two can never drift apart.
{ pkgs, lib, dartData, flutterData }:

let
  sanitize = import ./sanitize.nix;
  system = pkgs.stdenv.hostPlatform.system;

  forSystem = data: builtins.filter (e: e.system == system) data;
  dartEntries = forSystem dartData;
  flutterEntries = forSystem flutterData;

  mkDart = entry: import ./mk-dart.nix { inherit pkgs lib entry; };
  mkFlutter = entry: import ./mk-flutter.nix { inherit pkgs lib entry sanitize; };

  named = prefix: mk: entries:
    lib.listToAttrs (map (e: {
      name = "${prefix}_${sanitize e.version}";
      value = mk e;
    }) entries);

  # Newest entry in a channel (null if the channel has no build for this system).
  latestIn = entries: channel:
    let inChannel = builtins.filter (e: e.channel == channel) entries;
    in
    if inChannel == [ ] then null
    else lib.foldl'
      (acc: e: if builtins.compareVersions e.version acc.version > 0 then e else acc)
      (builtins.head inChannel)
      inChannel;

  # `<prefix>` = latest stable, `<prefix>_beta` / `<prefix>_dev` = latest of each.
  aliases = prefix: mk: entries:
    lib.listToAttrs (lib.concatMap
      (channel:
        let e = latestIn entries channel; in
        lib.optional (e != null) {
          name = if channel == "stable" then prefix else "${prefix}_${channel}";
          value = mk e;
        })
      [ "stable" "beta" "dev" ]);

  dartPkgs = named "dart" mkDart dartEntries // aliases "dart" mkDart dartEntries;
  flutterPkgs = named "flutter" mkFlutter flutterEntries
    // aliases "flutter" mkFlutter flutterEntries;
in
dartPkgs
// flutterPkgs
# `nix run` with no attr -> latest stable Flutter (falls back to Dart).
// lib.optionalAttrs (flutterPkgs ? flutter) { default = flutterPkgs.flutter; }
// lib.optionalAttrs (!(flutterPkgs ? flutter) && dartPkgs ? dart) {
  default = dartPkgs.dart;
}
