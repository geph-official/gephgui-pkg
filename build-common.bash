# build-common.bash — sourced by the build-*.bash scripts after they cd to the
# repo root. Not a standalone script.
#
# This checkout may be shared between several build machines (Syncthing, NFS,
# ...) with the Windows, macOS and Linux builds running CONCURRENTLY on
# different machines. To make that safe, a build must not mutate anything
# inside the shared checkout: two machines writing gephgui/node_modules,
# gephgui/dist or a cargo target/ tree at the same time would corrupt each
# other's builds (and thrash the sync). So every path a build writes lives
# under a machine-LOCAL root instead: sources are staged (copied) into it, all
# intermediates land in it, and only the finished artifact is published back
# into ./output/ — under a per-OS name, so no two machines ever write the same
# shared file.
#
# The exceptions, deliberate and safe:
#   - output/: final artifacts only, per-OS filenames, written via publish()
#     (temp file + rename) so other machines never sync a half-written file
#     under its final name.
#   - blobs/linux-x64: written only by build-flatpak.bash, read only by the
#     flatpak manifest on the same machine.
#   - .git: the submodule-bootstrap loops init MISSING submodules on first run.
#     Do that initial clone/init on one machine and let it sync before running
#     builds concurrently.

# Machine-local root for everything a build writes. $HOME/.cache is assumed to
# be local to the machine; override with GEPHGUI_PKG_BUILD_ROOT if you sync
# your home directory too.
LOCAL_BUILD_ROOT="${GEPHGUI_PKG_BUILD_ROOT:-${XDG_CACHE_HOME:-$HOME/.cache}/gephgui-pkg}"
LOCAL_SRC="$LOCAL_BUILD_ROOT/src"

# One shared cargo target dir under the local root: keeps geph5/target &co out
# of the synced checkout, and makes rebuilds incremental (cargo install would
# otherwise rebuild from scratch in a temp dir every run). On git-bash, cargo
# is a native Windows binary that would misread a /c/Users/... POSIX path in an
# environment variable (argv gets auto-converted, env does not), so hand it a
# C:/Users/... mixed path via cygpath.
if command -v cygpath >/dev/null 2>&1; then
    CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$(cygpath -m "$LOCAL_BUILD_ROOT")/target}"
else
    CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$LOCAL_BUILD_ROOT/target}"
fi
export CARGO_TARGET_DIR

# copy_tree SRC DST [EXCLUDE...] — mirror SRC into DST, excludes being
# root-anchored paths relative to SRC. mtimes are preserved, so cargo/npm see
# unchanged files as unchanged and rebuilds stay incremental. Excluded paths
# already present in DST are left alone (that's how node_modules survives
# restaging). Uses rsync where available; git-bash has no rsync, so fall back
# to rm + (GNU) tar, carrying DST's node_modules across the wipe to keep npm
# installs incremental there too.
copy_tree() {
    local src="$1" dst="$2"
    shift 2
    mkdir -p "$dst"
    if command -v rsync >/dev/null 2>&1; then
        local args=(-a --delete)
        local ex
        for ex in "$@"; do args+=(--exclude "/$ex"); done
        rsync "${args[@]}" "$src/" "$dst/"
    else
        local keep=""
        if [ -d "$dst/gephgui/node_modules" ]; then
            keep="$dst.keep-node_modules"
            rm -rf "$keep"
            mv "$dst/gephgui/node_modules" "$keep"
        fi
        rm -rf "$dst"
        mkdir -p "$dst"
        local args=(--anchored)
        local ex
        for ex in "$@"; do args+=(--exclude "./$ex"); done
        (cd "$src" && tar -cf - "${args[@]}" .) | (cd "$dst" && tar -xf -)
        if [ -n "$keep" ] && [ -d "$dst/gephgui" ]; then
            rm -rf "$dst/gephgui/node_modules"
            mv "$keep" "$dst/gephgui/node_modules"
        fi
    fi
}

# Stage gephgui-wry and geph5 side by side under $LOCAL_SRC, mirroring the repo
# layout — gephgui-wry's Cargo.toml [patch] entries point at ../geph5/…, so the
# two must stay siblings (the flatpak manifest stages them the same way).
# Build-artifact dirs are excluded: the frontend is npm-built in the STAGED
# copy (build_frontend), never in the shared checkout.
stage_gephgui_wry() {
    copy_tree gephgui-wry "$LOCAL_SRC/gephgui-wry" .git target gephgui/node_modules gephgui/dist
}
stage_geph5() {
    copy_tree geph5 "$LOCAL_SRC/geph5" .git target
}
stage_sources() {
    echo ">> staging sources into $LOCAL_SRC"
    stage_gephgui_wry
    stage_geph5
}

# Build the frontend in the staged copy; rust-embed then embeds
# $LOCAL_SRC/gephgui-wry/gephgui/dist when the staged crate is compiled.
build_frontend() {
    (cd "$LOCAL_SRC/gephgui-wry/gephgui" && npm i -f && npm run build)
}

# publish SRC DST — drop a finished artifact into the shared output/ via a
# temp file + same-directory rename, so machines syncing output/ never see a
# half-written file under its final name.
publish() {
    local src="$1" dst="$2"
    local tmp
    tmp="$(dirname "$dst")/.$(basename "$dst").partial"
    cp "$src" "$tmp"
    mv -f "$tmp" "$dst"
}
