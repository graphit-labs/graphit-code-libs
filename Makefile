.PHONY: lancedb-native bundle

PLATFORM ?=
LANCEDB_CACHE ?= $(CURDIR)/.cache/lancedb
LANCEDB_LIB_DIR ?= $(CURDIR)/.native
DIST_DIR ?= $(CURDIR)/dist

lancedb-native:
	@test -n "$(PLATFORM)" || { echo "PLATFORM is required" >&2; exit 1; }
	bash scripts/build-lancedb.sh "$(PLATFORM)" "$(LANCEDB_CACHE)" "$(LANCEDB_LIB_DIR)"

bundle: lancedb-native
	bash scripts/package-native.sh "$(PLATFORM)" "$(LANCEDB_LIB_DIR)" "$(DIST_DIR)"
