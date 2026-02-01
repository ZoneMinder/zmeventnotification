#!/bin/bash
# Fake detection hook for testing tag_detected_objects.
#
# Usage:
#   1. Set the labels you want to test:
#        export ZM_FAKE_LABELS="person,cat,shovel"
#      Or edit the DEFAULT below.
#
#   2. Edit zmeventnotification.ini:
#        event_start_hook = '/var/lib/zmeventnotification/bin/zm_detect_fake.sh'
#        use_hook_description = yes
#        tag_detected_objects = yes
#
#   3. Start the ES, then trigger an event:
#        sudo -u www-data zmu --alarm --monitor <mid>
#
#   4. Verify in MariaDB:
#        SELECT * FROM Tags;
#        SELECT * FROM Events_Tags;
#
# Arguments from ES (same as zm_event_start.sh):
#   $1 = eventId, $2 = monitorId, $3 = monitorName, $4 = cause

# --- Configure labels here or via ZM_FAKE_LABELS env var ---
DEFAULT="person,cat"
LABELS_CSV="${ZM_FAKE_LABELS:-$DEFAULT}"

IFS=',' read -ra LABEL_ARRAY <<< "$LABELS_CSV"

# Build detection text and JSON in the format ES expects:
#   <text>--SPLIT--<json_array>
DET_TEXT="[s] detected:"
JSON="["
FIRST=1
for label in "${LABEL_ARRAY[@]}"; do
  label=$(echo "$label" | xargs)  # trim whitespace
  if [[ $FIRST -eq 1 ]]; then
    FIRST=0
  else
    DET_TEXT+=","
    JSON+=","
  fi
  DET_TEXT+="${label}:99%"
  JSON+="{\"type\":\"object\",\"label\":\"${label}\",\"box\":[0,0,100,100],\"confidence\":\"0.99\"}"
done
JSON+="]"

echo "${DET_TEXT}--SPLIT--${JSON}"
exit 0
