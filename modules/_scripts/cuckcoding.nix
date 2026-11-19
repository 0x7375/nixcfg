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
    set -Eeuo pipefail

    PROGRAM=''${0##*/}
    BRANCH=''${AI_IMPORT_BRANCH:-ai-import}
    MAIN_BRANCH=''${AI_IMPORT_MAIN_BRANCH:-main}
    LAST_REF="refs/ai-import/last-squashed/$MAIN_BRANCH/$BRANCH"
    PUSH_GUARD_REMOTE=__ai_import_push_disabled__

    usage() {
      cat <<USAGE
    Usage: $PROGRAM [path/to/archive.zip]
           $PROGRAM merge

    Import the newest ZIP from ~/downloads or ~/Downloads (must be under one hour
    old), or supply an explicit ZIP path to skip that age check.

    Each import is committed to '$BRANCH'. The merge command squashes changes
    since the previous merge into one commit on '$MAIN_BRANCH', asking for a
    commit message, without leaving the import branch or pushing anything.
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

    repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || die 'run this inside the target Git repository'
    cd "$repo_root"
    git rev-parse --verify HEAD >/dev/null 2>&1 || die 'repository needs an initial commit'
    git check-ref-format --branch "$BRANCH" >/dev/null 2>&1 || die "invalid branch: $BRANCH"
    git check-ref-format --branch "$MAIN_BRANCH" >/dev/null 2>&1 || die "invalid main branch: $MAIN_BRANCH"
    git check-ref-format "$LAST_REF" || die "invalid tracking ref: $LAST_REF"

    # Other local changes must not be absorbed into an archive commit. Explicit
    # manual deletions are the one exception: ZIPs can restore them if present.
    check_clean_except_deletions() {
      git diff --cached --quiet || die 'staged changes found; commit or unstage them first'
      local other_changes untracked
      other_changes=$(git diff --name-status --diff-filter=ACMRTUXB)
      untracked=$(git ls-files --others --exclude-standard)
      [[ -z $other_changes && -z $untracked ]] || die 'uncommitted edits/untracked files found; only tracked deletions are allowed'
    }

    # Color newly added file paths without changing Git --stat alignment.
    print_stat() {
      local dir=$1 line col path
      local green=$'\033[32m' reset=$'\033[0m'
      local -a added_paths=()
      mapfile -d ''' -t added_paths < <(git -C "$dir" diff --cached --name-only --diff-filter=A -z HEAD)
      while IFS= read -r line; do
        if [[ $line == *' | '* ]]; then
          col=''${line%% | *}
          col=''${col#"''${col%%[![:space:]]*}"}
          col=''${col%"''${col##*[![:space:]]}"}
          for path in "''${added_paths[@]}"; do
            if [[ $col == "$path" ]]; then
              line=''${line/"$col"/"$green$col$reset"}
              break
            fi
          done
        fi
        printf '%s\n' "$line"
      done < <(git -C "$dir" -c core.quotePath=false --no-pager diff --cached --stat \
        --stat-name-width=200 --color=always --no-ext-diff --find-renames HEAD --)
    }

    # Squash only the increment since the last successful publication. Using
    # `git merge --squash` repeatedly causes conflicts because main does not
    # share the import commits' ancestry.
    merge_imports() {
      git show-ref --verify --quiet "refs/heads/$MAIN_BRANCH" || die "branch '$MAIN_BRANCH' not found"
      git show-ref --verify --quiet "refs/heads/$BRANCH" || die "branch '$BRANCH' not found"
      [[ -z $(git status --porcelain) ]] || die 'commit or discard local changes before merging'

      # If running on main, get it out of the way for the temporary main worktree.
      if [[ $(git branch --show-current) == "$MAIN_BRANCH" ]]; then
        git switch --quiet "$BRANCH"
      fi

      local last tip main_tree c tmp merge_dir count
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
      # This is a detached *temporary checkout* of main, not a branch switch in
      # the user's working directory. The real main ref moves only upon commit.
      git worktree add --quiet "$merge_dir" "$MAIN_BRANCH" || die 'cannot open a temporary main worktree'

      # All possible merge conflicts stay in the temporary worktree. Any failure
      # leaves the user's main branch and working directory unchanged.
      local patch="$tmp/increment.patch"
      git diff --binary --full-index --no-ext-diff "$last" "$tip" -- > "$patch"
      if [[ -s $patch ]]; then
        if ! git -C "$merge_dir" apply --index --3way "$patch" > "$tmp/apply.log" 2>&1; then
          cat "$tmp/apply.log" >&2
          git worktree remove --force "$merge_dir" >/dev/null 2>&1 || true
          rm -rf -- "$tmp"
          die "could not apply imports to $MAIN_BRANCH; branch was not changed"
        fi
      fi

      if git -C "$merge_dir" diff --cached --quiet; then
        git update-ref "$LAST_REF" "$tip"
        git worktree remove --force "$merge_dir" >/dev/null 2>&1 || true
        rm -rf -- "$tmp"
        printf 'No file changes to publish.\n'
        exit 0
      fi

      printf 'Squash %s import commit(s) into %s\n\n' "$count" "$MAIN_BRANCH"
      git -C "$merge_dir" --no-pager diff --cached --stat --color=always

      # Open the configured Git editor with no prefilled commit message.
      if ! git -C "$merge_dir" -c commit.template=/dev/null commit --quiet; then
        git worktree remove --force "$merge_dir" >/dev/null 2>&1 || true
        rm -rf -- "$tmp"
        die 'commit canceled or failed; main was not changed'
      fi
      git update-ref "$LAST_REF" "$tip"
      git worktree remove --force "$merge_dir" >/dev/null 2>&1 || true
      rm -rf -- "$tmp"
    }

    if [[ ''${1-} == merge ]]; then
      merge_imports
      exit 0
    fi

    # Resolve the archive before switching branches.
    if (( $# == 1 )); then
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
      [[ -n $latest_archive ]] || die 'no ZIP archive in ~/downloads or ~/Downloads'
      age=$(( $(date +%s) - latest_mtime ))
      (( age >= 0 && age < 3600 )) || die 'newest ZIP must be less than one hour old; pass a path to override'
      archive=$(realpath -e -- "$latest_archive") || die "cannot resolve archive: $latest_archive"
    fi
    [[ -f $archive && ''${archive,,} == *.zip ]] || die "not a ZIP file: $archive"
    check_clean_except_deletions
    unzip -tqq "$archive" >/dev/null || die 'invalid ZIP archive'

    tmp=$(mktemp -d "''${TMPDIR:-/tmp}/ai-import-extract.XXXXXX")
    aux_tmp=$(mktemp -d "''${TMPDIR:-/tmp}/ai-import-preview.XXXXXX")
    preview_worktree=
    cleanup() {
      [[ -z $preview_worktree ]] || git worktree remove --force "$preview_worktree" >/dev/null 2>&1 || true
      rm -rf -- "$tmp" "$aux_tmp"
    }
    trap cleanup EXIT
    unzip -q "$archive" -d "$tmp" || die 'failed to extract ZIP'

    shopt -s dotglob nullglob
    entries=("$tmp"/*)
    shopt -u dotglob nullglob
    if (( ''${#entries[@]} == 1 )) && [[ -d ''${entries[0]} ]]; then
      source_dir=''${entries[0]}
    else
      source_dir=$tmp
    fi

    if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
      git switch --quiet "$BRANCH"
    else
      git switch --quiet -c "$BRANCH"
    fi
    git branch --unset-upstream "$BRANCH" >/dev/null 2>&1 || true
    git config --local "branch.$BRANCH.pushRemote" "$PUSH_GUARD_REMOTE"
    check_clean_except_deletions
    mapfile -d ''' -t pending_deletions < <(git ls-files --deleted -z)
    kept_deletions=()
    for path in "''${pending_deletions[@]}"; do
      [[ -e "$source_dir/$path" || -L "$source_dir/$path" ]] || kept_deletions+=("$path")
    done

    preview_dir="$aux_tmp/preview"
    git worktree add --quiet --detach "$preview_dir" HEAD
    preview_worktree=$preview_dir
    rsync_options=(-a --checksum --exclude=.git)
    rsync "''${rsync_options[@]}" "$source_dir/" "$preview_dir/" || die 'preview failed'
    for path in "''${kept_deletions[@]}"; do
      rm -f -- "$preview_dir/$path"
    done

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

    printf 'Archive: %s\n\n' "''${archive##*/}"
    print_stat "$preview_dir"

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
    rsync "''${rsync_options[@]}" "$source_dir/" "$repo_root/" || die 'rsync failed; inspect the working tree'
    if [[ -s $pathspec_file ]]; then
      GIT_LITERAL_PATHSPECS=1 git add -A --pathspec-from-file="$pathspec_file" --pathspec-file-nul
    fi
    archive_name=''${archive##*/}
    git commit --quiet --allow-empty -m "Import archive: $archive_name" -m "$changes"
  '';
}
