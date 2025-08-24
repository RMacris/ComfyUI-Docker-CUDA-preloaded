#!/bin/bash
set -euo pipefail

# Enable extended globbing for robust trimming patterns like +([[:space:]])
shopt -s extglob

# Source common configuration
source /usr/local/bin/config.sh

# Optional: self-heal any directories that accidentally contain CR (\r)
heal_cr_dirs() {
  local fixed=0
  shopt -s nullglob
  for d in "$CUSTOM_DIR"/*; do
    if [[ -d "$d" && "$d" == *$'\r'* ]]; then
      local new_path="${d//$'\r'/}"
      log "WARN" "Fixing directory name with CR: $(basename "$d") -> $(basename "$new_path")"
      mv -T -- "$d" "$new_path" || log "ERROR" "Failed to rename $d to $new_path"
    fi
  done
  shopt -u nullglob
}

# Function: track commits for extensions
track_extension_commit() {
  local dir="$1"
  local name=$(basename "$dir")
  local last_commit_file="$LAST_DIR/${name}.commit"
  local new_commit old_commit branch

  # Get new commit
  new_commit=$(git -C "$dir" rev-parse HEAD 2>/dev/null) || {
    log "ERROR" "Failed to get commit hash for $name"
    return 1
  }

  # Compare with old commit
  old_commit=""
  if [ -f "$last_commit_file" ]; then
    old_commit=$(<"$last_commit_file")
  fi

  if [ "$new_commit" != "$old_commit" ]; then
    echo "$new_commit" >"$last_commit_file"
    log "INFO" "New commit detected for $name: $new_commit"
    return 0 # Changes detected
  else
    log "INFO" "No changes in $name (commit: $new_commit)"
    return 1 # No changes
  fi
}

# Function: install extension dependencies
install_extension_deps() {
  local dir="$1"
  local name=$(basename "$dir")

  if [ -f "$dir/requirements.txt" ]; then
    log "INFO" "Installing dependencies for $name"
    if pip install --no-cache-dir -r "$dir/requirements.txt"; then
      log "INFO" "Successfully installed dependencies for $name"
      return 0
    else
      log "WARN" "Failed to install dependencies for $name"
      return 1
    fi
  else
    log "INFO" "No requirements.txt found for $name"
    return 0
  fi
}

# Parse extensions from config file with CRLF/BOM sanitization
EXTENSIONS=()
log "INFO" "Parsing extensions configuration"

# Read the config file line-by-line and sanitize Windows CRLF and BOM
while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
  # Remove UTF-8 BOM if present and strip carriage returns anywhere on the line
  raw_line="${raw_line#$'\ufeff'}"
  raw_line="${raw_line//$'\r'/}"

  # Strip inline comments starting with # or ; and trim surrounding whitespace
  line="${raw_line%%[#;]*}"
  line="${line##+([[:space:]])}"
  line="${line%%+([[:space:]])}"

  # Skip empty lines and section headers like [group]
  [[ -z "$line" || "$line" =~ ^\[ ]] && continue

  EXTENSIONS+=("$line")
done </app/extensions.conf

log "INFO" "== Processing Extensions =="
log "INFO" "Found ${#EXTENSIONS[@]} extensions to process"

# Optional self-heal for previously created directories with CR in their names
if [[ "${SELF_HEAL_CR_DIRS:-1}" == "1" ]]; then
  heal_cr_dirs || true
fi

for url in "${EXTENSIONS[@]}"; do
  # Sanitize URL again defensively (remove CR, BOM, surrounding whitespace)
  url="${url#$'\ufeff'}"
  url="${url//$'\r'/}"
  url="${url##+([[:space:]])}"
  url="${url%%+([[:space:]])}"

  # Derive a clean repository name without trailing slashes or .git
  repo_part="${url##*/}"
  repo_part="${repo_part%/}"
  repo_part="${repo_part%.git}"
  name="$repo_part"

  # Fallback: if name is still empty, skip
  if [[ -z "$name" ]]; then
    log "WARN" "Could not derive repository name from URL: $url"
    continue
  fi

  # Ensure name has no stray control characters or whitespace
  name="${name//$'\r'/}"
  name="${name//$'\n'/}"
  name="${name##+([[:space:]])}"
  name="${name%%+([[:space:]])}"

  target="$CUSTOM_DIR/$name"

  log "INFO" "Processing extension: $name from $url"

  # Clone or update the repository
  if ! git_clone_or_update "$target" "$url"; then
    log "WARN" "Failed to update/clone extension: $name, skipping dependency installation"
    continue
  fi

  # Check if there are new commits
  if track_extension_commit "$target"; then
    # Only install dependencies if there are new commits
    install_extension_deps "$target" || log "WARN" "Dependency installation issues for $name, but continuing"
  else
    log "INFO" "No changes detected for $name, skipping dependency installation"
  fi
done

log "INFO" "== Extensions initialization complete =="
