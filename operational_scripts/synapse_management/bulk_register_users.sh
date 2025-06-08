#!/usr/bin/env bash
#
# Bulk‑register users on Synapse.
#   • Assumes the running container is named "matrix-synapse"
#   • Assumes /data/homeserver.yaml inside the container
#   • Edits welcome passwords if they re‑run (--exists-ok keeps idempotent)

set -euo pipefail

CONTAINER="synapse"
HOMESERVER_YAML="/data/homeserver.yaml"
INTERNAL_URL="http://localhost:8008"

# username      password             admin_flag   (true → admin, false → normal)
USERLIST_FILE="userlist.txt"

if [[ ! -r "$USERLIST_FILE" ]]; then
  echo "Error: User list file '$USERLIST_FILE' not found or not readable."
  echo "Please create '$USERLIST_FILE' with lines: <username> <password> <admin_flag> (e.g. eliza Chatbot%16lbz false)"
  exit 1
fi

while read -r user pass admin; do
  # Skip empty lines or lines starting with #
  [[ -z "$user" || "$user" =~ ^# ]] && continue

  echo "Creating or updating $user …"

  # Build options: set --no-admin unless $admin is true
  admin_opt="--no-admin"
  [[ "$admin" == "true" ]] && admin_opt=""

  docker exec -i "$CONTAINER" register_new_matrix_user \
      -c "$HOMESERVER_YAML" \
      -u "$user" \
      -p "$pass" \
      $admin_opt \
      --exists-ok

    role="User"
    [ "$admin" = "true" ] && role="Admin"
    printf "  → %-12s  temp‑password: %s  (%s)\n" \
        "@${user}:chat.ratimics.com" "$pass" "$role"
done < "$USERLIST_FILE"

echo "Done! Users can log in at https://chat.ratimics.com and should change their passwords ASAP."
