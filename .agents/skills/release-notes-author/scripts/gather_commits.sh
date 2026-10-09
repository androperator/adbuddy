#!/usr/bin/env bash

set -euo pipefail

usage() {
  printf 'usage: .agents/skills/release-notes-author/scripts/gather_commits.sh <start-tag> <end-ref>\n' >&2
  printf '  <start-tag>  must be an existing git tag (exclusive lower bound)\n' >&2
  printf '  <end-ref>    a git tag, branch name, or commit SHA (inclusive upper bound)\n' >&2
  printf '               when a tag, uses the tag creation date as the release date\n' >&2
  printf '               when a branch or SHA, uses the commit committer date\n' >&2
}

die() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "$repo_root" ]] || die "not inside a git repository"
cd "$repo_root"

if [[ $# -ne 2 ]]; then
  usage
  exit 1
fi

START_TAG="$1"
END_TAG="$2"

require_cmd git
require_cmd sort

git rev-parse -q --verify "refs/tags/$START_TAG" >/dev/null || die "tag '$START_TAG' not found"
START_COMMIT="$(git rev-parse -q --verify "refs/tags/$START_TAG^{commit}")"

# Resolve release date: prefer annotated/lightweight tag creation date; fall back to
# committer date when END_TAG is a branch name or commit SHA (pre-tag workflow).
release_date="$(git for-each-ref --format='%(creatordate:short)' "refs/tags/$END_TAG")"
if [[ -z "$release_date" ]]; then
  release_date="$(git log -1 --format='%cs' "${END_TAG}^{commit}" 2>/dev/null)" || true
  [[ -n "$release_date" ]] || die "ref '$END_TAG' not found or resolves to no commits"
fi

END_COMMIT="$(git rev-parse -q --verify "${END_TAG}^{commit}")"
git merge-base --is-ancestor "$START_COMMIT" "$END_COMMIT" || die "start tag must be an ancestor of end ref"

printf 'RELEASE_DATE: %s\n' "$release_date"

TMP_PATHS_FILE="$(mktemp "${TMPDIR:-/tmp}/release-notes-paths.XXXXXX")"
TMP_DELETED_FILE="$(mktemp "${TMPDIR:-/tmp}/release-notes-deleted.XXXXXX")"
TMP_SORTED_PATHS_FILE="$(mktemp "${TMPDIR:-/tmp}/release-notes-sorted.XXXXXX")"

cleanup() {
  rm -f "$TMP_PATHS_FILE" "$TMP_DELETED_FILE" "$TMP_SORTED_PATHS_FILE"
}

trap cleanup EXIT

path_type() {
  case "$1" in
    Tests/**|.agents/**|.github/**|scripts/**|docs/internal/**|CHANGELOG.md)
      printf 'infra' ;;
    Package.swift|VERSION|*.plist)
      printf 'config' ;;
    Sources/**|Resources/**|vendor/**|docs/**|README.md)
      printf 'src' ;;
    *) printf 'infra' ;;
  esac
}

is_release_ceremony_subject() {
  local subject="$1"

  case "$subject" in
    "docs(release): update published version to "*|"chore(release): bump version to "*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

collect_commit_files() {
  local sha="$1"

  while IFS=$'\t' read -r status path_a path_b; do
    [[ -n "${status:-}" ]] || continue

    local path=""
    case "$status" in
      D)
        path="$path_a"
        printf '%s\n' "$path" >>"$TMP_DELETED_FILE"
        ;;
      R*|C*)
        path="$path_b"
        ;;
      *)
        path="$path_a"
        ;;
    esac

    [[ -n "$path" ]] || continue
    printf '%s\n' "$path" >>"$TMP_PATHS_FILE"
  done < <(git diff-tree --no-commit-id --name-status --diff-filter=ACRMD -r -m "$sha")
}

while IFS= read -r sha; do
  [[ -n "$sha" ]] || continue
  : >"$TMP_PATHS_FILE"
  : >"$TMP_DELETED_FILE"
  collect_commit_files "$sha"

  sort -u "$TMP_PATHS_FILE" >"$TMP_SORTED_PATHS_FILE"

  local_subject="$(git log -1 --format='%s' "$sha")"
  has_app=0
  has_docs=0
  has_mcp=0
  has_named_surface=0
  has_src_in_surface=0

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    type="$(path_type "$path")"
    deleted=""
    if grep -Fxq -- "$path" "$TMP_DELETED_FILE"; then
      deleted=1
    fi

    case "$type" in
      src|generated|config)
        case "$path" in
          Sources/ADBuddy/**|Sources/ADBuddyCore/**|Resources/**|vendor/**|Package.swift|VERSION)
            has_app=1
            case "$path" in Sources/ADBuddyCore/**) has_mcp=1 ;; esac
            has_named_surface=1
            if [[ "$type" == "src" ]]; then
              has_src_in_surface=1
            fi
            ;;
          Sources/ADBuddyMCP/**)
            has_mcp=1
            has_named_surface=1
            if [[ "$type" == "src" ]]; then
              has_src_in_surface=1
            fi
            ;;
          docs/**|README.md)
            has_docs=1
            has_named_surface=1
            if [[ "$type" == "src" ]]; then
              has_src_in_surface=1
            fi
            ;;
        esac
    esac
  done <"$TMP_SORTED_PATHS_FILE"

  classification="drop:infra"
  if [[ "$has_src_in_surface" -eq 1 ]]; then
    classification="keep"
  elif [[ "$has_named_surface" -eq 1 ]]; then
    classification="drop:no-src"
  fi

  # Dedicated published-version follow-up commits are release ceremony, not
  # changelog-worthy product or docs changes, even when they touch authored docs.
  if is_release_ceremony_subject "$local_subject"; then
    classification="drop:infra"
  fi

  printf '=== COMMIT %s ===\n' "$sha"
  printf 'SUBJECT: %s\n' "$local_subject"
  if [[ "$local_subject" =~ \(\#([0-9]+)\)$ ]]; then
    printf 'PR: #%s\n' "${BASH_REMATCH[1]}"
  fi

  surfaces=()
  if [[ "$has_app" -eq 1 ]]; then
    surfaces+=("app")
  fi
  if [[ "$has_docs" -eq 1 ]]; then
    surfaces+=("docs")
  fi
  if [[ "$has_mcp" -eq 1 ]]; then
    surfaces+=("mcp")
  fi
  if [[ "${#surfaces[@]}" -gt 0 ]]; then
    printf 'SURFACES: %s\n' "${surfaces[*]}"
  fi

  printf 'CLASSIFICATION: %s\n' "$classification"
  printf 'FILES:\n'

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    type="$(path_type "$path")"
    deleted=""
    if grep -Fxq -- "$path" "$TMP_DELETED_FILE"; then
      deleted='[deleted]'
    fi
    printf '  %s  %s[%s]\n' "$path" "$deleted" "$type"
  done <"$TMP_SORTED_PATHS_FILE"

  if [[ "$classification" == "keep" ]]; then
    body="$(git log -1 --format='%b' "$sha")"
    if [[ -n "$body" ]]; then
      printf 'BODY:\n'
      while IFS= read -r line || [[ -n "$line" ]]; do
        printf '  %s\n' "$line"
      done <<<"$body"
    fi
  fi

  printf '=== END ===\n'
done < <(git log --reverse --format="%H" "$START_COMMIT..$END_COMMIT")
