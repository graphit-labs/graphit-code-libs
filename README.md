# Graphit Code native libraries

This repository publishes immutable, verified native dependency bundles used by Graphit Code builds.

Each release contains one archive for Linux amd64, macOS arm64, and Windows amd64. Every archive has a sibling `.sha256` file, an internal `SHA256SUMS`, and a `manifest.json` recording the exact Graphit Code source, LanceDB revisions and patch, LadybugDB versions, and ONNX Runtime versions.

The release workflow builds Graphit's patched LanceDB on the matching GitHub-hosted operating system. LadybugDB, its HTTPFS extension, and ONNX Runtime are downloaded from their pinned upstream releases and verified before packaging.

Recipe versions are immutable. Updating any source, patch, dependency, or checksum requires a new `NATIVE_RECIPE_VERSION`.
