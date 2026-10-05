# List non-persisted files
config: pkgs:
pkgs.writeShellApplication {
  name = "fs-diff";
  runtimeInputs = with pkgs; [
    gawk
    util-linux
  ];
  excludeShellChecks = [ "SC2016" ];
  text = ''
    set -euo pipefail

    DEVICE="${config.fileSystems."/".device}"

    TMPDIR=$(mktemp -d)
    MNT_ROOT="$TMPDIR/root"
    MNT_HOME="$TMPDIR/home"
    MNT_PERSIST="$TMPDIR/persist"

    cleanup() {
        sudo umount "$MNT_PERSIST" 2>/dev/null || true
        sudo umount "$MNT_ROOT" 2>/dev/null || true
        sudo umount "$MNT_HOME" 2>/dev/null || true
        rmdir "$MNT_PERSIST" "$MNT_ROOT" "$MNT_HOME" "$TMPDIR" 2>/dev/null || true
    }
    trap cleanup EXIT

    mkdir -p "$MNT_HOME" "$MNT_ROOT" "$MNT_PERSIST"
    sudo mount -o ro,noatime,subvol=@root "$DEVICE" "$MNT_ROOT"
    sudo mount -o ro,noatime,subvol=@home "$DEVICE" "$MNT_HOME"
    sudo mount -o ro,noatime,subvol=@persist "$DEVICE" "$MNT_PERSIST"

    EXCLUDES=(
        "$MNT_ROOT/nix"
        "$MNT_ROOT/persist"
        "$MNT_ROOT/home"
        "$MNT_ROOT/var/log"
        "$MNT_ROOT/swap"
        "$MNT_ROOT/boot"
        "$MNT_ROOT/proc"
        "$MNT_ROOT/sys"
        "$MNT_ROOT/dev"
        "$MNT_ROOT/run"
        "$MNT_ROOT/tmp"
    )

    while IFS= read -r mnt; do
        EXCLUDES+=("$MNT_ROOT$mnt")
        [[ $mnt == /home/* ]] && EXCLUDES+=("$MNT_HOME''${mnt#/home}")
    done < <(findmnt -l -n -o TARGET | grep -vE '^(/|/home|/nix|/persist)$')

    # Collapse directories with many entries into "dir/* (N entries)".
    # exempt: colon-separated dirs that are skipped as collapse candidates and
    # "reset" the depth counter.
    collapse_awk='
    BEGIN {
        split("/var/lib:.cache:.local:.local/share:.local/state", a, ":")
        for (i in a) exempt_set[a[i]] = 1
    }
    {
        sub(/^[[:space:]]+/, "")
        lines[NR] = $0
        n = split($0, a, "/")
        path = a[1]
        for (i = 2; i < n; i++) {
            path = (path == "") ? "/" a[i] : path "/" a[i]
            cnt[path]++
        }
    }
    END {
        min_depth = 2
        threshold = 10
        prev_top = ""
        for (i = 1; i <= NR; i++) {
            p = lines[i]
            n = split(p, a, "/")
            top = (a[1] == "" ? "/" a[2] : a[1])
            if (prev_top != "" && top != prev_top) print ""
            prev_top = top
            path = a[1]
            exempt_at = exempt_set[path] ? 1 : 0
            collapsed = 0
            for (j = 2; j < n; j++) {
                path = (path == "") ? "/" a[j] : path "/" a[j]
                if (exempt_set[path]) { exempt_at = j; continue }
                eff_depth = exempt_at ? j - exempt_at : j - 1
                if (eff_depth >= (exempt_at ? 1 : min_depth) && cnt[path] > threshold) {
                    if (!shown[path]) {
                        print "  " path "/* (" cnt[path] " entries)"
                        shown[path] = 1
                    }
                    collapsed = 1
                    break
                }
            }
            if (!collapsed) print "  " p
        }
    }'

    prune_args=()
    for d in "''${EXCLUDES[@]}"; do
        prune_args+=(-path "$d" -prune -o)
    done

    echo "@root:"
    sudo find "$MNT_ROOT" "''${prune_args[@]}" -type f -print |
        while IFS= read -r full_path; do
            rel="''${full_path#"$MNT_ROOT"}"
            [[ -e "$MNT_PERSIST$rel" ]] || echo "  $rel"
        done | gawk "$collapse_awk"

    MANIFEST_CONTENT=$(cat /var/lib/hjem/manifest-ayko.json 2>/dev/null || echo "")

    echo "@home:"
    sudo find "$MNT_HOME" "''${prune_args[@]}" -type f -print |
        while IFS= read -r full_path; do
            rel="/home/''${full_path#"$MNT_HOME"/}"
            [[ -e "$MNT_PERSIST$rel" ]] && continue
            [[ "$MANIFEST_CONTENT" == *"$rel"* ]] && continue
            
            echo "  ''${rel#/home/ayko/}"
        done | gawk "$collapse_awk"
  '';
}
