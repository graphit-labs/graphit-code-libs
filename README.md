# Graphit Code native libraries

This repository publishes immutable, verified native dependency bundles used by Graphit Code builds.

Each release contains one archive for Linux amd64, macOS arm64, and Windows amd64. Every archive has a sibling `.sha256` file, an internal `SHA256SUMS`, and a `manifest.json` recording the exact Graphit Code source, LanceDB revisions and patch, LadybugDB versions, and ONNX Runtime versions.

The release workflow builds Graphit's patched LanceDB on the matching GitHub-hosted operating system. LadybugDB, its HTTPFS extension, and ONNX Runtime are downloaded from their pinned upstream releases and verified before packaging.

Recipe versions are immutable. Updating any source, patch, dependency, or checksum requires a new `NATIVE_RECIPE_VERSION`.

Graphit Code pins the recipe and each platform archive digest in its own `native-deps.env`. Local builds and Graphit Code CI download the same release asset, verify the outer archive digest and the archive's internal checksums, then install the libraries into their existing build locations. This keeps native dependency artifacts out of Graphit Code product releases and avoids rebuilding them for every checkout or release.

## Publishing an update

Update every version, source revision, and upstream checksum in `native-deps.env`, increment `NATIVE_RECIPE_VERSION`, and push the change to `main`. The workflow publishes a release only after all three native runner jobs build and package successfully; an existing recipe tag is never overwritten.
