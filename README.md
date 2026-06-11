# dash-flake

Pinned **Dart** and **Flutter** SDK binaries — every `stable`, `beta`, and `dev`
release from Google's archive — exposed as Nix packages, so you never have to wait
for `nixpkgs` to catch up.

Supported systems: **`x86_64-linux`** and **`aarch64-darwin`**.

Each release is a selectable package attribute:

```
dart_3_5_0        flutter_3_24_0
dart_3_13_0_167_1_beta   flutter_3_45_0_0_1_pre
…
```

Version strings are sanitized into attr names by replacing `.`, `-` and `+` with `_`
(so `3.45.0-0.1.pre` → `flutter_3_45_0_0_1_pre`).

Convenience aliases always point at the newest build per channel:

| alias | meaning |
| --- | --- |
| `dart` / `flutter` | latest **stable** |
| `dart_beta` / `flutter_beta` | latest **beta** |
| `dart_dev` / `flutter_dev` | latest **dev** |
| `default` | latest stable Flutter (so plain `nix run` works) |

## Quick start

```bash
# Run a pinned version straight from the flake
nix run github:CarlosMendonca/dash-flake#flutter_3_24_0 -- --version
nix run github:CarlosMendonca/dash-flake#dart_3_5_0 -- --version

# Latest stable
nix run github:CarlosMendonca/dash-flake#flutter -- doctor

# Drop a version into your shell
nix shell github:CarlosMendonca/dash-flake#dart_3_5_0
```

## Use in a flake

```nix
{
  inputs.dash.url = "github:CarlosMendonca/dash-flake";

  outputs = { self, nixpkgs, dash }: {
    # ...packages from dash.packages.${system}.flutter_3_24_0 etc.
  };
}
```

### devenv

```nix
# devenv.nix
{ inputs, pkgs, ... }:
{
  packages = [
    inputs.dash.packages.${pkgs.system}.flutter_3_24_0
    inputs.dash.packages.${pkgs.system}.dart_3_5_0
  ];
}
```

### Home-Manager

```nix
# home.nix
{ inputs, pkgs, ... }:
{
  home.packages = [ inputs.dash.packages.${pkgs.system}.flutter_3_24_0 ];
}
```

### Overlay (NixOS / any nixpkgs instance)

Fold every `dart_*` / `flutter_*` package onto your own `pkgs`:

```nix
{
  nixpkgs.overlays = [ inputs.dash.overlays.default ];
}
# then, anywhere with `pkgs`:
#   environment.systemPackages = [ pkgs.flutter_3_24_0 pkgs.dart_3_5_0 ];
```

## How it works

- `data/dart.json` and `data/flutter.json` hold one entry per
  `(version, channel, system)` with the download URL and a `sha256`.
- `flake.nix` reads those files and turns each entry into a package
  (`lib/mk-dart.nix`, `lib/mk-flutter.nix`); `lib/mk-packages.nix` assembles the
  full set shared by `packages.<system>` and `overlays.default`.

**Dart** is self-contained, so on Linux it's just `autoPatchelfHook`; on macOS the
arm64 binaries run as-is.

**Flutter** is trickier: its tarball downloads the engine + bundled Dart SDK on
first run and then executes those binaries. To make that work on NixOS, the Flutter
package:

1. copies the SDK to a writable cache dir (`$XDG_CACHE_HOME/dash-flake/flutter-<ver>`)
   on first run, and
2. on Linux runs everything inside a `buildFHSEnv` that provides the standard loader
   and libraries, so the runtime-downloaded engine binaries resolve their deps.

`PUB_CACHE` is redirected to `$XDG_CACHE_HOME/dash-flake/pub-cache` so nothing tries
to write into the read-only store.

> Linux desktop builds work out of the box. Android/iOS toolchains are **not**
> bundled — bring your own (e.g. via `androidenv` / Xcode).

## Updating the data

```bash
nix run .#update                       # all channels (stable + beta + dev)
DASH_CHANNELS="stable beta" nix run .#update   # restrict Dart channels (faster)
```

The updater never downloads an SDK archive: Flutter ships a per-release `sha256` in
its metadata, and Dart ships a `.sha256sum` sidecar next to each zip. A GitHub Action
(`.github/workflows/update.yml`) runs this daily and opens a PR when new releases
appear.
