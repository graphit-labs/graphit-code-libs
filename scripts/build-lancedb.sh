#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_dir=$(cd "$script_dir/.." && pwd)
source "$repo_dir/native-deps.env"

platform=${1:?platform is required}
cache_dir=${2:?cache directory is required}
output_dir=${3:?output directory is required}
patch_file="$repo_dir/patches/lancedb-go-main.patch"
source_dir="$cache_dir/src"

case "$platform" in
  linux-amd64) library=liblancedb_go.so ;;
  darwin-arm64) library=liblancedb_go.dylib ;;
  windows-amd64) library=lancedb_go.dll ;;
  *) echo "unsupported platform: $platform" >&2; exit 1 ;;
esac

hash_text_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sed 's/\r$//' "$1" | sha256sum | awk '{print $1}'
  else
    sed 's/\r$//' "$1" | shasum -a 256 | awk '{print $1}'
  fi
}

if [ "$(hash_text_file "$patch_file")" != "$LANCEDB_PATCH_SHA256" ]; then
  echo "LanceDB patch does not match LANCEDB_PATCH_SHA256" >&2
  exit 1
fi

mkdir -p "$cache_dir" "$output_dir"
if [ ! -d "$source_dir/.git" ]; then
  git clone -q "$LANCEDB_GO_REPOSITORY" "$source_dir"
fi

git -C "$source_dir" fetch -q origin "$LANCEDB_GO_REF" 2>/dev/null || git -C "$source_dir" fetch -q origin
git -C "$source_dir" checkout -q "$LANCEDB_GO_REF"
git -C "$source_dir" restore --source="$LANCEDB_GO_REF" --worktree --staged -- \
  include/lancedb.h rust/Cargo.lock rust/Cargo.toml \
  rust/src/connection.rs rust/src/data.rs rust/src/index.rs \
  rust/src/schema_evolve.rs rust/src/table.rs
git -C "$source_dir" apply --unidiff-zero --check "$patch_file"
git -C "$source_dir" apply --unidiff-zero "$patch_file"

if ! grep -q 'crate-type = \["staticlib", "cdylib"\]' "$source_dir/rust/Cargo.toml"; then
  sed -i.bak 's/crate-type = \["staticlib"\]/crate-type = ["staticlib", "cdylib"]/' "$source_dir/rust/Cargo.toml"
fi
if ! grep -q 'features = \["aws"\]' "$source_dir/rust/Cargo.toml"; then
  sed -i.bak 's/tag = "v0.24.0", default-features = false }/tag = "v0.24.0", default-features = false, features = ["aws"] }/' "$source_dir/rust/Cargo.toml"
fi

(
  cd "$source_dir/rust"
  if ! grep -q "version = \"$LANCEDB_ETHNUM_VERSION\"" Cargo.lock; then
    cargo update -p ethnum --precise "$LANCEDB_ETHNUM_VERSION" >/dev/null
  fi
  cargo build --release
)

source_library="$source_dir/rust/target/release/$library"
if [ ! -s "$source_library" ]; then
  echo "expected $library in $source_dir/rust/target/release" >&2
  exit 1
fi
cp -L "$source_library" "$output_dir/$library"
printf '%s %s\n' "$LANCEDB_GO_REF" "$LANCEDB_PATCH_GIT_BLOB" > "$output_dir/lancedb_go_build.sha"
