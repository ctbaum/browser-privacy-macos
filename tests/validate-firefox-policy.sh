#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
temporary=$(mktemp -d)
schema_url='https://raw.githubusercontent.com/mozilla-firefox/firefox/FIREFOX_158_0_RELEASE/browser/components/enterprisepolicies/schemas/policies-schema.json'
trap 'rm -rf "$temporary"' EXIT

curl --fail --location --silent --show-error "$schema_url" > "$temporary/policies-schema.json"
jq '
  . as $schema
  | {
      "$schema": $schema["$schema"],
      "definitions": $schema.definitions,
      "type": "object",
      "additionalProperties": false,
      "required": ["policies"],
      "properties": {
        "policies": (
          $schema
          | del(."$schema", .definitions)
          | .additionalProperties = false
        )
      }
    }
' "$temporary/policies-schema.json" > "$temporary/policies-file-schema.json"

check-jsonschema --schemafile "$temporary/policies-file-schema.json" "$repo_dir/firefox-policies.json"
printf '%s\n' '{"policies":{"TypoPolicy":true}}' > "$temporary/invalid-policy.json"
if check-jsonschema --schemafile "$temporary/policies-file-schema.json" "$temporary/invalid-policy.json" >/dev/null 2>&1; then
  echo "Firefox schema validation unexpectedly accepted an unknown policy." >&2
  exit 1
fi
