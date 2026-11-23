#!/usr/bin/env bash
# Stores an OpenAI API key as a Secret in the selected Namespace and registers an
# `openai` credential source that may send it only to api.openai.com. Prints the
# source ID for deploy.sh. The key is read from a file and never appears in a
# command argument or in output.
#
#   OCC_URL=... OCC_SERVICE_KEY_FILE=... OCC_NAMESPACE=... OPENAI_API_KEY_FILE=... ./model-source.sh
set -euo pipefail                                                      # stop on the first failing command or unset variable
umask 077                                                              # files this script writes are readable only by you
: "${OCC_URL:?}" "${OCC_SERVICE_KEY_FILE:?}" "${OCC_NAMESPACE:?}"      # require the endpoint, the key file and the Namespace ID
: "${OPENAI_API_KEY_FILE:?Set OPENAI_API_KEY_FILE to a private file holding the OpenAI API key}"  # require the model key file
OCC=${OCC:-occ}                                                        # the occ binary to run
SOURCE_NAME=${SOURCE_NAME:-jira-summary-model}                         # name for both the Secret and the source
tmp=$(mktemp -d)                                                       # private scratch folder for the request documents
trap 'rm -rf "$tmp"' EXIT                                              # delete it, with the key copy, when the script ends

jq -Rs --arg name "$SOURCE_NAME" '{name: $name, value: gsub("\n"; "")}' \
  < "$OPENAI_API_KEY_FILE" > "$tmp/secret.json"                        # build {name, value} from the key file, newline stripped
$OCC secret create --file "$tmp/secret.json" -o json > "$tmp/secret.out"  # store it as a Namespace Secret; reply is metadata only
jq --arg name "$SOURCE_NAME" '{name: $name, type: "openai",
  secrets: {api_key: .ref}, config: {authorized_base_url: "https://api.openai.com/v1"}}' \
  "$tmp/secret.out" > "$tmp/source.json"                               # source document: points at the Secret's ref, limits the host
$OCC credential-source create --file "$tmp/source.json" -o json | jq -er '.id'  # register the source with the gateway; print its ID
