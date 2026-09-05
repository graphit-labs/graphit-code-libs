#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd "$script_dir/.." && pwd)
source "$repo_dir/native-deps.env"

platform=${1:?platform is required}
source_dir=$(cd "${2:?graphit-code source directory is required}" && pwd)
output_dir=${3:?output directory is required}
mkdir -p "$output_dir"
output_dir=$(cd "$output_dir" && pwd)

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

download() {
  local url=$1
  local destination=$2
  local expected=$3
  curl -fSL --retry 5 --retry-delay 5 --retry-all-errors "$url" -o "$destination.tmp"
  local actual
  actual=$(hash_file "$destination.tmp")
  if [ "$actual" != "$expected" ]; then
    echo "checksum mismatch for $url" >&2
    exit 1
  fi
  mv "$destination.tmp" "$destination"
}

if [ "$(git -C "$source_dir" rev-parse HEAD)" != "$GRAPHIT_CODE_REF" ]; then
  echo "graphit-code checkout does not match GRAPHIT_CODE_REF" >&2
  exit 1
fi
if [ "$(hash_file "$source_dir/patches/lancedb-go-main.patch")" != "$LANCEDB_PATCH_SHA256" ]; then
  echo "LanceDB patch does not match LANCEDB_PATCH_SHA256" >&2
  exit 1
fi

case "$platform" in
  linux-amd64)
    lancedb_name=liblancedb_go.so
    lbug_archive=liblbug-linux-x86_64.tar.gz
    lbug_sha=$LBUG_LINUX_AMD64_SHA256
    lbug_extension_platform=linux_amd64
    lbug_extension_sha=$LBUG_EXT_LINUX_AMD64_SHA256
    ort_archive=onnxruntime-linux-x64-${ORT_VERSION}.tgz
    ort_sha=$ORT_LINUX_AMD64_SHA256
    ort_name=libonnxruntime.so
    ;;
  darwin-arm64)
    lancedb_name=liblancedb_go.dylib
    lbug_archive=liblbug-osx-arm64.tar.gz
    lbug_sha=$LBUG_DARWIN_ARM64_SHA256
    lbug_extension_platform=osx_arm64
    lbug_extension_sha=$LBUG_EXT_DARWIN_ARM64_SHA256
    ort_archive=onnxruntime-osx-arm64-${ORT_VERSION}.tgz
    ort_sha=$ORT_DARWIN_ARM64_SHA256
    ort_name=libonnxruntime.dylib
    ;;
  windows-amd64)
    lancedb_name=lancedb_go.dll
    lbug_archive=liblbug-windows-x86_64.zip
    lbug_sha=$LBUG_WINDOWS_AMD64_SHA256
    lbug_extension_platform=win_amd64
    lbug_extension_sha=$LBUG_EXT_WINDOWS_AMD64_SHA256
    ort_archive=onnxruntime-win-x64-${ORT_VERSION}.zip
    ort_sha=$ORT_WINDOWS_AMD64_SHA256
    ort_name=onnxruntime.dll
    ;;
  *)
    echo "unsupported platform: $platform" >&2
    exit 1
    ;;
esac

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT
bundle_name="graphit-native-${NATIVE_RECIPE_VERSION}-${platform}"
bundle_dir="$work_dir/$bundle_name"
mkdir -p "$bundle_dir/lancedb" "$bundle_dir/ladybug" "$bundle_dir/onnxruntime"

cp -L "$source_dir/.native/$lancedb_name" "$bundle_dir/lancedb/$lancedb_name"
cp "$source_dir/.native/lancedb_go_build.sha" "$bundle_dir/lancedb/lancedb_go_build.sha"

download \
  "https://github.com/LadybugDB/ladybug/releases/download/v${LBUG_VERSION}/${lbug_archive}" \
  "$work_dir/$lbug_archive" "$lbug_sha"
if [[ "$lbug_archive" == *.zip ]]; then
  unzip -q "$work_dir/$lbug_archive" -d "$bundle_dir/ladybug"
else
  tar xzf "$work_dir/$lbug_archive" -C "$bundle_dir/ladybug"
fi

download \
  "https://extension.ladybugdb.com/v${LBUG_EXT_VERSION}/${lbug_extension_platform}/httpfs/libhttpfs.lbug_extension" \
  "$bundle_dir/ladybug/httpfs.lbug_extension" "$lbug_extension_sha"

download \
  "https://github.com/microsoft/onnxruntime/releases/download/v${ORT_VERSION}/${ort_archive}" \
  "$work_dir/$ort_archive" "$ort_sha"
mkdir -p "$work_dir/ort"
if [[ "$ort_archive" == *.zip ]]; then
  unzip -q "$work_dir/$ort_archive" -d "$work_dir/ort"
else
  tar xzf "$work_dir/$ort_archive" -C "$work_dir/ort"
fi
ort_source=$(find "$work_dir/ort" -type f -name "$ort_name" -o -type l -name "$ort_name" | head -n 1)
if [ -z "$ort_source" ]; then
  echo "ONNX Runtime library $ort_name was not found" >&2
  exit 1
fi
cp -L "$ort_source" "$bundle_dir/onnxruntime/$ort_name"

cat > "$bundle_dir/manifest.json" <<EOF
{
  "schema": 1,
  "recipe": "${NATIVE_RECIPE_VERSION}",
  "platform": "${platform}",
  "graphit_code_ref": "${GRAPHIT_CODE_REF}",
  "lancedb_go_ref": "${LANCEDB_GO_REF}",
  "lancedb_core_ref": "${LANCEDB_CORE_REF}",
  "lancedb_patch_sha256": "${LANCEDB_PATCH_SHA256}",
  "ladybug_go_version": "${LBUG_GO_VERSION}",
  "ladybug_version": "${LBUG_VERSION}",
  "ladybug_extension_version": "${LBUG_EXT_VERSION}",
  "onnxruntime_go_version": "${ORT_GO_VERSION}",
  "onnxruntime_version": "${ORT_VERSION}"
}
EOF

(
  cd "$bundle_dir"
  while IFS= read -r file; do
    digest=$(hash_file "$file")
    printf '%s  %s\n' "$digest" "${file#./}"
  done < <(find . -type f ! -name SHA256SUMS | sort) > SHA256SUMS
)

archive="$output_dir/$bundle_name.tar.gz"
tar -C "$work_dir" -czf "$archive" "$bundle_name"
archive_digest=$(hash_file "$archive")
printf '%s  %s\n' "$archive_digest" "$(basename "$archive")" > "$archive.sha256"
echo "$archive"
