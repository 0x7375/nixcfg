{ pkgs, ... }:

pkgs.writeShellApplication {
  name = "ai-import";

  runtimeInputs = with pkgs; [
    coreutils
    findutils
    gawk
    git
    rsync
    unzip
  ];

  text = ''
    # Import a chatbot-generated project ZIP as a commit on a local-only Git branch.
    # Usage: ai-import [path/to/archive.zip]

    set -Eeuo pipefail

    PROGRAM=''${0##*/}
    BRANCH=''${AI_IMPORT_BRANCH:-ai-import}
    PUSH_GUARD_REMOTE=__ai_import_push_disabled__

    usage() {
      cat <<USAGE
    Usage: $PROGRAM [path/to/archive.zip]

    Without an argument, imports the most recently modified ZIP in ~/downloads or
    ~/Downloads, provided it is no more than one hour old. An explicit path skips
    that freshness check.

    Imports on the local '$BRANCH' branch, switching to it automatically. The
    script never pushes. Files omitted from the ZIP are never deleted automatically.
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

    # Resolve the archive before changing directory to the repository root.
    if (( $# == 1 )); then
      command -v realpath >/dev/null 2>&1 || die "realpath is required"
      archive=$(realpath -e -- "$1") || die "cannot resolve archive: $1"
    else
      latest_archive=
      latest_mtime=0
      for downloads_dir in "$HOME/downloads" "$HOME/Downloads"; do
        [[ -d $downloads_dir ]] || continue
        while IFS= read -r -d ''' candidate; do
          mtime=$(stat -c '%Y' -- "$candidate") || continue
          if (( mtime > latest_mtime )); then
            latest_mtime=$mtime
            latest_archive=$candidate
          fi
        done < <(find "$downloads_dir" -maxdepth 1 -type f -iname '*.zip' -print0)
      done

      [[ -n $latest_archive ]] || die "no ZIP archive found in ~/downloads or ~/Downloads"

      now=$(date +%s)
      age=$(( now - latest_mtime ))
      (( age >= 0 )) || die "newest ZIP has a future modification time: $latest_archive"
      (( age < 3600 )) || die "newest ZIP is older than one hour ($(age / 60) minutes): $latest_archive; pass an explicit path to import it anyway"
      command -v realpath >/dev/null 2>&1 || die "realpath is required"
      archive=$(realpath -e -- "$latest_archive") || die "cannot resolve archive: $latest_archive"
    fi

    [[ -f $archive ]] || die "not a regular file: $archive"
    [[ ''${archive,,} == *.zip ]] || die "archive must have a .zip extension: $archive"
    command -v unzip >/dev/null 2>&1 || die "unzip is required"
    command -v rsync >/dev/null 2>&1 || die "rsync is required"
    command -v git >/dev/null 2>&1 || die "git is required"
    command -v find >/dev/null 2>&1 || die "find is required"

    # Locate the Git worktree.
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || die "run this inside the target Git repository"
    cd "$repo_root"
    git rev-parse --verify HEAD >/dev/null 2>&1 || die "repository needs at least one commit"
    git check-ref-format --branch "$BRANCH" >/dev/null 2>&1 || die "invalid branch name: $BRANCH"

    # Do not accidentally absorb staged changes, edits, or untracked files. The
    # one intentional exception is deleted tracked files: those are the user's
    # explicit cleanup of files omitted by an earlier archive.
    check_clean_except_deletions() {
      if ! git diff --cached --quiet; then
        die "the Git index has staged changes; commit or unstage them before importing"
      fi
      other_changes=$(git diff --name-status --diff-filter=ACMRTUXB)
      untracked=$(git ls-files --others --exclude-standard)
      if [[ -n $other_changes || -n $untracked ]]; then
        printf '%s: refusing to import over other local changes. Only manually deleted tracked files are allowed.\n' "$PROGRAM" >&2
        [[ -z $other_changes ]] || printf '\nModified/other tracked files:\n%s\n' "$other_changes" >&2
        [[ -z $untracked ]] || printf '\nUntracked files:\n%s\n' "$untracked" >&2
        exit 1
      fi
    }
    check_clean_except_deletions

    # Validate and extract the archive before changing branches.
    unzip -tqq "$archive" >/dev/null || die "ZIP integrity check failed: $archive"
    tmp=$(mktemp -d "''${TMPDIR:-/tmp}/ai-import-extract.XXXXXX") || die "could not create temporary directory"
    aux_tmp=$(mktemp -d "''${TMPDIR:-/tmp}/ai-import-work.XXXXXX") || die "could not create temporary directory"
    preview_worktree=
    cleanup() {
      if [[ -n "$preview_worktree" ]]; then
        git worktree remove --force "$preview_worktree" >/dev/null 2>&1 || true
      fi
      rm -rf -- "$tmp" "$aux_tmp"
    }
    trap cleanup EXIT
    unzip -q "$archive" -d "$tmp" || die "could not extract archive"

    # Chatbot ZIPs commonly contain one enclosing project directory. Strip it
    # when it is the archive's only top-level entry; otherwise use the ZIP root.
    shopt -s dotglob nullglob
    entries=("$tmp"/*)
    shopt -u dotglob nullglob
    if (( ''${#entries[@]} == 1 )) && [[ -d ''${entries[0]} ]]; then
      source_dir=''${entries[0]}
    else
      source_dir=$tmp
    fi

    # Create the branch on first use, then automatically return to it on every
    # later import. The branch is created from whichever branch is current now.
    if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
      git switch --quiet "$BRANCH"
    else
      git switch --quiet -c "$BRANCH"
    fi
    # Keep it local-only: no upstream, and even a plain `git push` targets a
    # deliberately nonexistent remote. The script itself never invokes push.
    git branch --unset-upstream "$BRANCH" >/dev/null 2>&1 || true
    git config --local "branch.$BRANCH.pushRemote" "$PUSH_GUARD_REMOTE"
    check_clean_except_deletions

    # Remember tracked files the user manually deleted. If the new ZIP contains
    # one, the overlay restores it; otherwise the deletion is included in this
    # archive's commit.
    mapfile -d ''' -t pending_deletions < <(git ls-files --deleted -z)

    kept_deletions=()
    for path in "''${pending_deletions[@]}"; do
      if [[ ! -e "$source_dir/$path" && ! -L "$source_dir/$path" ]]; then
        kept_deletions+=("$path")
      fi
    done

    # Build a temporary detached worktree to calculate the exact Git diff without
    # touching the real project before confirmation.
    preview_dir="$aux_tmp/preview"
    git worktree add --quiet --detach "$preview_dir" HEAD
    preview_worktree=$preview_dir

    # Overlay into the preview only. --delete is deliberately absent.
    rsync_options=(-a --checksum --exclude=.git)
    rsync "''${rsync_options[@]}" "$source_dir/" "$preview_dir/" || die "could not prepare preview"

    # Preserve manual deletions when the archive still omits those files.
    for path in "''${kept_deletions[@]}"; do
      rm -f -- "$preview_dir/$path"
    done

    # Stage only files supplied by the archive, plus manual deletions still absent
    # from it. New ignored files are not force-added.
    pathspec_file="$aux_tmp/pathspecs"
    : > "$pathspec_file"
    while IFS= read -r -d ''' path; do
      path=''${path#./}
      if git -C "$preview_dir" ls-files --error-unmatch -- "$path" >/dev/null 2>&1 || ! git -C "$preview_dir" check-ignore -q -- "$path"; then
        printf '%s\0' "$path" >> "$pathspec_file"
      fi
    done < <(
      cd "$source_dir"
      find . -mindepth 1 -path '*/.git' -prune -o \( -type f -o -type l \) -print0
    )
    for path in "''${kept_deletions[@]}"; do
      printf '%s\0' "$path" >> "$pathspec_file"
    done
    if [[ -s $pathspec_file ]]; then
      GIT_LITERAL_PATHSPECS=1 git -C "$preview_dir" add -A --pathspec-from-file="$pathspec_file" --pathspec-file-nul
    fi

    # Show the archive name and a short, coloured diff summary.
    printf 'Archive: %s\n\n' "''${archive##*/}"
    git -C "$preview_dir" --no-pager diff --cached --stat --color=always --no-ext-diff --find-renames HEAD --

    name_status=$(git -C "$preview_dir" diff --cached --name-status --find-renames)
    if [[ -n $name_status ]]; then
      changes=$(printf '%s\n' "$name_status" | awk '
        /^R[0-9]+[[:space:]]/ { print "Rename " $2 " -> " $3; next }
        $1 == "A" { print "Add " $2; next }
        $1 == "M" { print "Update " $2; next }
        $1 == "D" { print "Delete " $2; next }
        { print $1 " " $2 }
      ')
    else
      changes='No file changes.'
    fi

    printf '\nApply and commit? [y/N] '
    IFS= read -r answer || answer=
    [[ $answer == [yY] ]] || exit 0

    # Apply the same overlay to the real worktree, then stage the exact paths used
    # for the preview. Files omitted by the archive remain untouched.
    rsync "''${rsync_options[@]}" "$source_dir/" "$repo_root/" || die "rsync failed; inspect the working tree before running again"
    if [[ -s $pathspec_file ]]; then
      GIT_LITERAL_PATHSPECS=1 git add -A --pathspec-from-file="$pathspec_file" --pathspec-file-nul
    fi

    archive_name=''${archive##*/}
    git commit --quiet --allow-empty -m "Import archive: $archive_name" -m "$changes"
  '';
}
