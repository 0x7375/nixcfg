{ pkgs, ... }:

let
  importer =
    pkgs.writeText "ai-import.py"
      # py
      ''
        import json
        import os
        from pathlib import Path
        import shutil
        import stat
        import subprocess
        import sys
        import tempfile
        from zipfile import BadZipFile, ZipFile

        MANIFEST = ".ai-import.json"
        ERROR = (ValueError, OSError, RuntimeError, BadZipFile, subprocess.CalledProcessError)


        def git(repo, *args, data=None, literal=False):
            env = dict(os.environ, GIT_LITERAL_PATHSPECS="1") if literal else None
            return subprocess.run(
                ["git", "-C", str(repo), *args], input=data, stdout=subprocess.PIPE,
                check=True, env=env,
            ).stdout


        def lines0(data):
            return [os.fsdecode(item) for item in data.split(b"\0") if item]


        def paths0(paths):
            return b"".join(os.fsencode(path) + b"\0" for path in sorted(paths))


        def branch_tip(repo, branch):
            result = subprocess.run(
                ["git", "-C", str(repo), "show-ref", "--verify", "--hash", f"refs/heads/{branch}"],
                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
            )
            return result.stdout.strip() if result.returncode == 0 else None


        def checkout_state(repo):
            for marker in ("MERGE_HEAD", "CHERRY_PICK_HEAD", "REVERT_HEAD", "rebase-merge",
                           "rebase-apply", "sequencer", "BISECT_START"):
                if (repo / os.fsdecode(git(repo, "rev-parse", "--git-path", marker).strip())).exists():
                    raise ValueError("finish the Git operation in progress before importing")
            status = lines0(git(repo, "status", "--porcelain=v1", "-z",
                                "--untracked-files=all", "--ignore-submodules=none"))
            if any(not line.startswith(" D ") for line in status):
                raise ValueError("staged changes, edits or untracked files found")
            return (git(repo, "branch", "--show-current").strip(), git(repo, "rev-parse", "HEAD").strip(),
                    {line[3:] for line in status})


        def safe_path(path):
            if not isinstance(path, str) or any(ord(c) < 32 or ord(c) == 127 for c in path):
                raise ValueError(f"invalid path: {path!r}")
            parts = path.split("/")
            if (any(p in ("", ".", "..") or p.casefold() == ".git" for p in parts)
                    or "\\" in path or ":" in path):
                raise ValueError(f"unsafe path: {path!r}")
            return path


        def unique_object(pairs):
            result = {}
            for key, value in pairs:
                if key in result:
                    raise ValueError(f"duplicate manifest key: {key!r}")
                result[key] = value
            return result


        def manifest_actions(data):
            manifest = json.loads(data, object_pairs_hook=unique_object)
            if not isinstance(manifest, dict) or set(manifest) - {"delete", "rename"}:
                raise ValueError(f"{MANIFEST} accepts only delete and rename")
            delete = manifest.get("delete", [])
            rename = manifest.get("rename", {})
            if not isinstance(delete, list) or not isinstance(rename, dict):
                raise ValueError("delete must be an array and rename must map old paths to new paths")
            deletes = {safe_path(path) for path in delete}
            renames = {safe_path(old): safe_path(new) for old, new in rename.items()}
            paths = deletes | renames.keys() | set(renames.values())
            if len(paths) != len(delete) + 2 * len(renames):
                raise ValueError("delete and rename paths must be distinct")
            if any(path.rsplit("/", 1)[-1] == MANIFEST for path in paths):
                raise ValueError(f"{MANIFEST} is reserved")
            return deletes, renames


        def unpack(archive, repo_name, payload):
            with ZipFile(archive) as bundle:
                members = {}
                for info in bundle.infolist():
                    raw_name = info.orig_filename
                    is_dir = raw_name.endswith("/")
                    path = safe_path(raw_name[:-1] if is_dir else raw_name)
                    mode = stat.S_IFMT(info.external_attr >> 16)
                    if mode not in (0, stat.S_IFDIR if is_dir else stat.S_IFREG):
                        raise ValueError(f"ZIP member is a link or special file: {path!r}")
                    if path in members:
                        raise ValueError(f"duplicate ZIP member: {path!r}")
                    members[path] = info, is_dir

                for path in members:
                    for parent in Path(path).parents:
                        parent_entry = members.get(parent.as_posix())
                        if parent_entry is not None and not parent_entry[1]:
                            raise ValueError(f"ZIP file/directory conflict: {path!r}")

                roots = {path.partition("/")[0] for path in members}
                wrapper = ""
                if len(roots) == 1:
                    root = next(iter(roots))
                    if (root in (archive.stem, repo_name) or f"{root}/{MANIFEST}" in members
                            ) and any(path.startswith(root + "/") for path in members):
                        wrapper = root + "/"

                files = {path.removeprefix(wrapper): info
                         for path, (info, is_dir) in members.items() if not is_dir}
                if any(path.endswith("/" + MANIFEST) for path in files):
                    raise ValueError(f"{MANIFEST} must be at the ZIP root or inside its only wrapper")
                if MANIFEST in files:
                    deletes, renames = manifest_actions(bundle.read(files.pop(MANIFEST)))
                else:
                    deletes, renames = set(), {}

                if files.keys() & (deletes | renames.keys() | set(renames.values())):
                    raise ValueError("a manifest path also appears as a ZIP file")

                for path, info in files.items():
                    dest = payload / path
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    with bundle.open(info) as source, dest.open("xb") as target:
                        shutil.copyfileobj(source, target)
                    dest.chmod(0o755 if (info.external_attr >> 16) & 0o111 else 0o644)
                return set(files), deletes, renames


        def tracked_files(repo):
            tracked = {}
            for entry in lines0(git(repo, "ls-files", "--stage", "-z")):
                metadata, path = entry.split("\t", 1)
                tracked[path] = metadata.split(" ", 1)[0]
            return tracked


        def inspect_path(repo, path):
            dest = repo / path
            for parent in Path(path).parents:
                if parent == Path("."):
                    break
                directory = repo / parent
                if directory.is_symlink() or (directory.exists() and not directory.is_dir()):
                    raise ValueError(f"path crosses a symlink or file: {path!r}")
                if os.path.lexists(directory / ".git"):
                    raise ValueError(f"path crosses a nested Git checkout: {path!r}")
            if os.path.lexists(dest) and (dest.is_symlink() or not dest.is_file()):
                raise ValueError(f"path is a symlink, directory or special file: {path!r}")
            return dest


        def check_paths(repo, tracked, writes, removals):
            for path in writes | removals:
                dest = inspect_path(repo, path)
                mode = tracked.get(path)
                if (mode is not None and mode not in ("100644", "100755")) or any(
                    tracked.get(parent.as_posix()) == "160000" for parent in Path(path).parents
                ):
                    raise ValueError(f"path is a Git symlink or submodule: {path!r}")
                if mode is None and os.path.lexists(dest):
                    raise ValueError(f"would overwrite an untracked or ignored file: {path!r}")


        def ignored_paths(repo, paths):
            if not paths:
                return set()
            result = subprocess.run(
                ["git", "-C", str(repo), "check-ignore", "-z", "--stdin"],
                input=paths0(paths), stdout=subprocess.PIPE, check=False,
            )
            if result.returncode not in (0, 1):
                raise ValueError("could not check Git ignore rules")
            return set(lines0(result.stdout))


        def copy_file(source, dest):
            dest.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(dir=dest.parent, delete=False) as tmp:
                temp_path = Path(tmp.name)
            try:
                shutil.copyfile(source, temp_path)
                temp_path.chmod(stat.S_IMODE(source.stat().st_mode))
                temp_path.replace(dest)
            finally:
                temp_path.unlink(missing_ok=True)


        def overlay(repo, snapshot, writes, removals):
            for old in sorted(removals):
                (repo / old).unlink(missing_ok=True)
            for path in sorted(writes):
                copy_file(snapshot / path, repo / path)
            if writes or removals:
                git(repo, "add", "-A", "--pathspec-from-file=-", "--pathspec-file-nul",
                    data=paths0(writes | removals), literal=True)


        DIFF_ARGS = ("--find-renames", "--no-ext-diff", "--no-textconv", "HEAD", "--")


        def staged_changes(repo):
            entries = lines0(git(repo, "diff", "--cached", "--name-status", "-z", *DIFF_ARGS))
            changes = []
            index = 0
            while index < len(entries):
                status, path = entries[index:index + 2]
                index += 2
                if status.startswith(("R", "C")):
                    path = path + " -> " + entries[index]
                    index += 1
                changes.append((status[0], path))

            return changes


        def print_stat(repo):
            limit = 12
            changes = staged_changes(repo)
            colors = {"A": "\x1b[32m", "D": "\x1b[31m", "R": "\x1b[38;5;208m"}
            raw = git(repo, "-c", "core.quotePath=false", "--no-pager",
                      "diff", "--cached", "--stat", f"--stat-count={limit}", "--stat-name-width=200",
                      "--color=always", *DIFF_ARGS)
            index = 0
            for line in os.fsdecode(raw).splitlines():
                name, sep, counts = line.rpartition(" | ")
                if sep and index < min(limit, len(changes)):
                    color = colors.get(changes[index][0])
                    if color:
                        line = " " + color + name[1:] + "\x1b[0m" + sep + counts
                    index += 1
                print(line)
            for status, path in changes[limit:]:
                if status in ("D", "R"):
                    label = "Delete" if status == "D" else "Rename"
                    print(f" {colors[status]}{label} {path!r}\x1b[0m")


        def import_zip(repo, branch, archive, push_remote):
            original = checkout_state(repo)
            current_branch, head, manual_deletes = original
            branch_bytes = os.fsencode(branch)
            tip = branch_tip(repo, branch)
            if manual_deletes and current_branch != branch_bytes:
                raise ValueError("tracked deletions cannot be carried across a branch switch")
            if not archive.is_file() or archive.suffix.lower() != ".zip":
                raise ValueError(f"not a ZIP archive: {archive}")

            with tempfile.TemporaryDirectory(prefix="ai-import-") as tmp:
                snapshot = Path(tmp) / "files"
                preview = Path(tmp) / "preview"
                files, deletes, renames = unpack(archive, repo.name, snapshot)
                git(repo, "-c", "core.hooksPath=/dev/null", "worktree", "add", "--quiet", "--detach",
                    str(preview), os.fsdecode(tip or head))
                try:
                    tracked = tracked_files(preview)
                    removals = (manual_deletes - files) | deletes | renames.keys()
                    writes = files | set(renames.values())
                    if (deletes | renames.keys()) - tracked.keys():
                        raise ValueError("manifest source is not a tracked file: " +
                                         repr(sorted((deletes | renames.keys()) - tracked.keys())))
                    for old, new in renames.items():
                        if old in manual_deletes or new in tracked:
                            raise ValueError(f"rename needs an existing source and a new destination: {old!r} -> {new!r}")
                    check_paths(preview, tracked, writes, removals)
                    if current_branch == branch_bytes:
                        check_paths(repo, tracked, writes, removals)
                    for old, new in renames.items():
                        copy_file(preview / old, snapshot / new)

                    new_paths = writes - tracked.keys()
                    initially_ignored = ignored_paths(preview, new_paths)
                    if initially_ignored:
                        raise ValueError(f"ZIP would add ignored files: {sorted(initially_ignored)!r}")

                    overlay(preview, snapshot, writes, removals)
                    expected = git(preview, "write-tree")
                    print(f"Archive: {archive.name!r}  Branch: {branch}", flush=True)
                    if expected == git(preview, "rev-parse", "HEAD^{tree}"):
                        print("No file changes to import.")
                        return
                    print_stat(preview)
                    try:
                        answer = input("\nApply and commit? [y/N] ")
                    except EOFError:
                        return
                    if answer.lower() != "y":
                        return

                    if checkout_state(repo) != original or branch_tip(repo, branch) != tip:
                        raise ValueError("repository changed during review; rerun to preview again")
                    if current_branch != branch_bytes:
                        args = (branch,) if tip else ("-c", branch)
                        git(repo, "switch", "--quiet", "--no-overwrite-ignore", *args)
                    if checkout_state(repo) != (branch_bytes, tip or head, manual_deletes):
                        raise ValueError("checkout differs from the approved preview")
                    check_paths(repo, tracked, writes, removals)
                    local_ignored = ignored_paths(repo, new_paths)
                    if local_ignored:
                        raise ValueError(f"ZIP would add locally ignored files: {sorted(local_ignored)!r}")

                    try:
                        overlay(repo, snapshot, writes, removals)
                        if git(repo, "write-tree") != expected:
                            raise ValueError("staged changes differ from the preview")
                        git(repo, "config", "--local", f"branch.{branch}.pushRemote", push_remote)
                        labels = {"A": "Add", "D": "Delete", "M": "Update", "R": "Rename", "C": "Copy"}
                        summary = "\n".join(f"{labels.get(status, status)} {path}"
                                            for status, path in staged_changes(repo))
                        git(repo, "commit", "--quiet", "-m", f"Import archive: {archive.name}", "-m", summary)
                    except ERROR as exc:
                        raise ValueError(f"{exc}; inspect git status before retrying") from exc
                    commit = git(repo, "rev-parse", "--short", "HEAD").decode().strip()
                    print(f"Imported as {commit} on {branch}.")
                finally:
                    git(repo, "worktree", "remove", "--force", str(preview))


        if __name__ == "__main__":
            try:
                if sys.argv[1] == "--stat":
                    print_stat(Path(sys.argv[2]))
                else:
                    import_zip(Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3]), sys.argv[4])
            except ERROR as exc:
                sys.exit(f"ai-import: {exc}")
            except KeyboardInterrupt:
                sys.exit(130)
      '';
in
pkgs.writeShellApplication {
  name = "ai-import";

  runtimeInputs = with pkgs; [
    coreutils
    findutils
    git
    python3
  ];

  text = ''
    set -Eeuo pipefail

    PROGRAM=''${0##*/}
    BRANCH=''${AI_IMPORT_BRANCH:-ai-import}
    MAIN_BRANCH=''${AI_IMPORT_MAIN_BRANCH:-main}
    LAST_REF="refs/ai-import/last-squashed/$MAIN_BRANCH/$BRANCH"
    PUSH_GUARD_REMOTE=__ai_import_push_disabled__
    start_dir=$PWD

    usage() {
      cat <<USAGE
    Usage: $PROGRAM [path/to/archive.zip]
           $PROGRAM merge

    Import the newest ZIP from ~/downloads or ~/Downloads (must be under one hour
    old), or supply an explicit ZIP path to skip that age check.

    Each import is committed to '$BRANCH'. The merge command squashes changes
    since the previous merge into one commit on '$MAIN_BRANCH', asking for a
    commit message, without leaving the import branch or pushing anything.

    Archive paths are repository-relative. An optional .ai-import.json declares
    tracked files to delete and exact renames. Omitted paths are preserved.
    USAGE
    }

    die() {
      printf '%s: %s\n' "$PROGRAM" "$*" >&2
      exit 1
    }

    if (( $# > 1 )); then
      usage >&2
      exit 2
    fi

    if [[ ''${1-} == -h || ''${1-} == --help ]]; then
      usage
      exit 0
    fi

    [[ $BRANCH != "$MAIN_BRANCH" ]] || die 'import and main branches must be different'

    repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || die 'run this inside the target Git repository'
    cd "$repo_root"
    git rev-parse --verify HEAD >/dev/null 2>&1 || die 'repository needs an initial commit'
    git check-ref-format --branch "$BRANCH" >/dev/null 2>&1 || die "invalid branch: $BRANCH"
    git check-ref-format --branch "$MAIN_BRANCH" >/dev/null 2>&1 || die "invalid main branch: $MAIN_BRANCH"
    git check-ref-format "$LAST_REF" || die "invalid tracking ref: $LAST_REF"

    # Squash only the increment since the last successful publication. Using
    # `git merge --squash` repeatedly causes conflicts because main does not
    # share the import commits' ancestry.
    merge_imports() {
      git show-ref --verify --quiet "refs/heads/$MAIN_BRANCH" || die "branch '$MAIN_BRANCH' not found"
      git show-ref --verify --quiet "refs/heads/$BRANCH" || die "branch '$BRANCH' not found"
      [[ -z $(git status --porcelain) ]] || die 'commit or discard local changes before merging'

      # If running on main, get it out of the way for the temporary main worktree.
      if [[ $(git branch --show-current) == "$MAIN_BRANCH" ]]; then
        git switch --quiet --no-overwrite-ignore "$BRANCH"
      fi

      local last tip main_tree c count
      tip=$(git rev-parse "$BRANCH")
      if git show-ref --verify --quiet "$LAST_REF"; then
        last=$(git rev-parse "$LAST_REF")
        git merge-base --is-ancestor "$last" "$tip" || die 'import history was rewritten; reset the squash tracking reference manually'
      else
        # Recognize a prior manual squash when main has exactly the same tree as
        # an import commit. Otherwise start at the common ancestor.
        last=
        main_tree=$(git rev-parse "$MAIN_BRANCH^{tree}")
        while IFS= read -r c; do
          if [[ $(git rev-parse "$c^{tree}") == "$main_tree" ]]; then
            last=$c
            break
          fi
        done < <(git rev-list "$BRANCH")
        if [[ -z $last ]]; then
          last=$(git merge-base "$MAIN_BRANCH" "$BRANCH") || die 'no common base between branches'
        fi
      fi

      count=$(git rev-list --count "$last..$tip")
      if (( count == 0 )); then
        printf 'No new imports to squash.\n'
        exit 0
      fi

      tmp=$(mktemp -d "''${TMPDIR:-/tmp}/ai-import-merge.XXXXXX")
      merge_dir="$tmp/main"
      trap 'git worktree remove --force "$merge_dir" >/dev/null 2>&1 || true
            rm -rf -- "$tmp"' EXIT
      git worktree add --quiet "$merge_dir" "$MAIN_BRANCH" || die 'cannot open a temporary main worktree'

      # All possible merge conflicts stay in the temporary worktree. Any failure
      # leaves the user's main branch and working directory unchanged.
      local patch="$tmp/increment.patch"
      git diff --binary --full-index --no-ext-diff "$last" "$tip" -- > "$patch"
      if [[ -s $patch ]]; then
        if ! git -C "$merge_dir" apply --index --3way "$patch" > "$tmp/apply.log" 2>&1; then
          cat "$tmp/apply.log" >&2
          die "could not apply imports to $MAIN_BRANCH; branch was not changed"
        fi
      fi

      if git -C "$merge_dir" diff --cached --quiet; then
        git update-ref "$LAST_REF" "$tip"
        printf 'No file changes to publish.\n'
        exit 0
      fi

      printf 'Squash %s import commit(s) into %s\n\n' "$count" "$MAIN_BRANCH"
      python3 "${importer}" --stat "$merge_dir"

      # Open the configured Git editor with no prefilled commit message.
      if ! git -C "$merge_dir" -c commit.template=/dev/null commit --quiet; then
        die 'commit canceled or failed; main was not changed'
      fi
      git update-ref "$LAST_REF" "$tip"
    }

    if [[ ''${1-} == merge ]]; then
      merge_imports
      exit 0
    fi

    # Resolve the archive before switching branches.
    if (( $# == 1 )); then
      if [[ $1 == /* ]]; then
        archive=$1
      else
        archive="$start_dir/$1"
      fi
      archive=$(realpath -e -- "$archive") || die "cannot resolve archive: $1"
    else
      latest_archive=
      latest_mtime=0
      for downloads_dir in "$HOME/downloads" "$HOME/Downloads"; do
        [[ -d $downloads_dir ]] || continue
        while IFS= read -r -d "" candidate; do
          mtime=$(stat -c '%Y' -- "$candidate") || continue
          if (( mtime > latest_mtime )); then
            latest_mtime=$mtime
            latest_archive=$candidate
          fi
        done < <(find "$downloads_dir" -maxdepth 1 -type f -iname '*.zip' -print0)
      done
      [[ -n $latest_archive ]] || die 'no ZIP archive in ~/downloads or ~/Downloads'
      age=$(( $(date +%s) - latest_mtime ))
      (( age >= 0 && age < 3600 )) || die 'newest ZIP must be less than one hour old; pass a path to override'
      archive=$(realpath -e -- "$latest_archive") || die "cannot resolve archive: $latest_archive"
    fi
    exec python3 "${importer}" "$repo_root" "$BRANCH" "$archive" "$PUSH_GUARD_REMOTE"
  '';
}
