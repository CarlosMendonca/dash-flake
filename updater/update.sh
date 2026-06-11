#!/usr/bin/env bash
# Regenerates data/dart.json and data/flutter.json from Google's release archives.
#
# No SDK archive is ever downloaded: Flutter ships a per-release sha256 in its
# metadata JSON, and Dart ships a `.sha256sum` sidecar next to each zip. We only
# fetch those, so a full run is cheap enough for CI.
#
# Env knobs (all optional):
#   DASH_DATA_DIR   where to write the JSON files       (default: $PWD/data)
#   DASH_CHANNELS   space-separated channels for Dart   (default: "stable beta dev")
#   DASH_SKIP_DART / DASH_SKIP_FLUTTER  set to skip that generator (local testing)
#
# Dart generation is incremental: versions already present in dart.json are not
# re-fetched. Flutter is fully regenerated each run (only two HTTP requests).

set -euo pipefail

DATA_DIR="${DASH_DATA_DIR:-$PWD/data}"
CHANNELS="${DASH_CHANNELS:-stable beta dev}"

GCS_DART_LIST="https://www.googleapis.com/storage/v1/b/dart-archive/o"
DART_DL="https://storage.googleapis.com/dart-archive/channels"
FLUTTER_BASE="https://storage.googleapis.com/flutter_infra_release/releases"

# (system, dart-platform, dart-arch) triples we support.
DART_SYSTEMS=(
  "x86_64-linux:linux:x64"
  "aarch64-darwin:macos:arm64"
)

mkdir -p "$DATA_DIR"

log() { printf '[dash-update] %s\n' "$*" >&2; }

gen_flutter() {
  local out="$DATA_DIR/flutter.json"
  local tmp
  tmp="$(mktemp)"
  log "fetching Flutter release metadata"

  local linux_json macos_json
  linux_json="$(curl -fsSL "$FLUTTER_BASE/releases_linux.json")"
  macos_json="$(curl -fsSL "$FLUTTER_BASE/releases_macos.json")"

  # Linux ships x64; macOS ships arm64 (and x64, which we ignore).
  # Pre-2021 releases predate the dart_sdk_arch field and are all x64 on Linux,
  # so treat a missing arch as x64 (otherwise ~430 old stable/beta/dev versions,
  # including the entire historical dev channel, would be dropped).
  jq -c --arg system "x86_64-linux" '
    .base_url as $b
    | .releases[]
    | select(.dart_sdk_arch == "x64" or (.dart_sdk_arch == null))
    | { version, channel, system: $system, url: ($b + "/" + .archive), sha256 }
  ' <<<"$linux_json" >>"$tmp"

  jq -c --arg system "aarch64-darwin" '
    .base_url as $b
    | .releases[]
    | select(.dart_sdk_arch == "arm64")
    | { version, channel, system: $system, url: ($b + "/" + .archive), sha256 }
  ' <<<"$macos_json" >>"$tmp"

  jq -s 'unique_by([.version, .system]) | sort_by(.system, .version)' "$tmp" >"$out"
  rm -f "$tmp"
  log "wrote $out ($(jq length "$out") entries)"
}

gen_dart() {
  local out="$DATA_DIR/dart.json"
  local tmp
  tmp="$(mktemp)"

  # Seed with whatever we already have so we only fetch genuinely new versions.
  declare -A have=()
  if [[ -f "$out" ]]; then
    jq -c '.[]' "$out" >>"$tmp"
    while IFS= read -r key; do
      have["$key"]=1
    done < <(jq -r '.[] | "\(.version)|\(.system)"' "$out")
  fi

  local channel
  for channel in $CHANNELS; do
    log "listing Dart '$channel' versions"
    local prefix="channels/$channel/release/"
    local token=""
    while :; do
      local url="$GCS_DART_LIST?prefix=$prefix&delimiter=/"
      [[ -n "$token" ]] && url="$url&pageToken=$token"
      local resp
      resp="$(curl -fsSL "$url")"

      local ver
      while IFS= read -r ver; do
        [[ -z "$ver" || "$ver" == "latest" ]] && continue
        # Skip bare build-number dirs (e.g. 45692) that aren't real releases.
        [[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]] || continue
        local spec
        for spec in "${DART_SYSTEMS[@]}"; do
          local system plat arch
          IFS=: read -r system plat arch <<<"$spec"
          local key="$ver|$system"
          [[ -n "${have[$key]:-}" ]] && continue
          local zurl="$DART_DL/$channel/release/$ver/sdk/dartsdk-$plat-$arch-release.zip"
          local sum
          if sum="$(curl -fsSL "$zurl.sha256sum" 2>/dev/null)"; then
            sum="${sum%% *}" # "<hash>  dartsdk-...zip" -> "<hash>"
            [[ -z "$sum" ]] && continue
            jq -nc \
              --arg version "$ver" --arg channel "$channel" \
              --arg system "$system" --arg url "$zurl" --arg sha256 "$sum" \
              '{version:$version,channel:$channel,system:$system,url:$url,sha256:$sha256}' \
              >>"$tmp"
            have["$key"]=1
          fi
        done
      done < <(jq -r --arg p "$prefix" '.prefixes[]? | ltrimstr($p) | rtrimstr("/")' <<<"$resp")

      token="$(jq -r '.nextPageToken // empty' <<<"$resp")"
      [[ -z "$token" ]] && break
    done
  done

  jq -s 'unique_by([.version, .system]) | sort_by(.system, .version)' "$tmp" >"$out"
  rm -f "$tmp"
  log "wrote $out ($(jq length "$out") entries)"
}

[[ -n "${DASH_SKIP_FLUTTER:-}" ]] || gen_flutter
[[ -n "${DASH_SKIP_DART:-}" ]] || gen_dart
log "done"
