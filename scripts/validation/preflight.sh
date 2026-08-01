#!/usr/bin/env bash

set -euo pipefail

FAILED=0

required_files=(
  "sfdx-project.json"
  "force-app/main/default/applications/SocioWatch.app-meta.xml"
  "force-app/main/default/labels/CustomLabels.labels-meta.xml"
  "force-app/main/default/objects/SocioWatch_Configuration__c/SocioWatch_Configuration__c.object-meta.xml"
  "force-app/main/default/objects/SocioWatch_Mention__c/SocioWatch_Mention__c.object-meta.xml"
  "force-app/main/default/permissionsets/SocioWatch_Admin.permissionset-meta.xml"
  "force-app/main/default/permissionsets/SocioWatch_User.permissionset-meta.xml"
  "force-app/main/default/lwc/socioWatchSettings/socioWatchSettings.js-meta.xml"
  "force-app/main/default/lwc/socioWatchChat/socioWatchChat.js-meta.xml"
  "force-app/main/default/classes/SocioWatchApiClient.cls"
  "force-app/main/default/classes/SocioWatchSettingsController.cls"
  "force-app/main/default/classes/SocioWatchSyncController.cls"
  "force-app/main/default/classes/SocioWatchChatController.cls"
  "manifest/package.xml"
)

for file in "${required_files[@]}"; do
  if [[ ! -f "${file}" ]]; then
    echo "MISSING: ${file}"
    FAILED=1
  fi
done

echo "Checking for likely secrets..."

if grep -RInE \
  --exclude-dir=.git \
  --exclude="*.md" \
  '(Bearer[[:space:]]+[A-Za-z0-9._-]{12,}|api[_-]?key[[:space:]]*[:=][[:space:]]*["'\''][^"'\'']+|secret[[:space:]]*[:=][[:space:]]*["'\''][^"'\'']+)' \
  force-app scripts config manifest; then
  echo "Potential secret detected."
  FAILED=1
fi

echo "Checking prohibited direct AWS calls from LWC..."

if grep -RInE \
  '(fetch\(|XMLHttpRequest|execute-api\.)' \
  force-app/main/default/lwc; then
  echo "Direct external call detected in LWC."
  FAILED=1
fi

echo "Checking Apex sharing declarations..."

for file in force-app/main/default/classes/*.cls; do
  if grep -qE \
    'public (class|virtual class|abstract class|global class)' \
    "${file}"; then
    echo "Review explicit sharing: ${file}"
  fi
done

if [[ "${FAILED}" -ne 0 ]]; then
  echo "Preflight failed."
  exit 1
fi

echo "Preflight passed."
