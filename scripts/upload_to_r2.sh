#!/usr/bin/env bash
set -euo pipefail

# Upload exported HTML and audio files to Cloudflare R2 via rclone.
#
# Prerequisites:
#   1. brew install rclone
#   2. rclone config
#      - Type: s3
#      - Provider: Cloudflare
#      - Access key + secret: Cloudflare dashboard > R2 > Manage R2 API Tokens
#      - Endpoint: https://<ACCOUNT_ID>.eu.r2.cloudflarestorage.com
#        (use .eu. for WEUR buckets, plain for default)
#   3. python scripts/export_for_r2.py

CLEAN=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --clean) CLEAN=true; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

REMOTE="${R2_REMOTE:-cloudflare r2}"
BUCKET="oald10"
TRANSFERS="${R2_TRANSFERS:-16}"

if [[ ! -d export/html ]]; then
    echo "Error: export/html/ not found. Run: python scripts/export_for_r2.py" >&2
    exit 1
fi

if [[ ! -f export/audio_filelist.txt ]]; then
    echo "Error: export/audio_filelist.txt not found. Run: python scripts/export_for_r2.py" >&2
    exit 1
fi

if [[ "$CLEAN" == true ]]; then
    echo "=== Cleaning bucket ${BUCKET} ==="
    rclone purge "${REMOTE}:${BUCKET}/" --s3-no-check-bucket 2>/dev/null || true
fi

echo "=== Uploading HTML files ==="
rclone copy export/html/ "${REMOTE}:${BUCKET}/html/" \
    --progress --transfers "$TRANSFERS" --retries 5 --low-level-retries 10 \
    --s3-no-check-bucket

echo "=== Uploading audio files ==="
rclone copy oxford.dictionary/Contents/ "${REMOTE}:${BUCKET}/audio/" \
    --files-from export/audio_filelist.txt \
    --progress --transfers "$TRANSFERS" --retries 5 --low-level-retries 10 \
    --s3-no-check-bucket

echo "=== Uploading audio packs ==="
if [[ -d export/audio-packs ]]; then
    rclone copy export/audio-packs/ "${REMOTE}:${BUCKET}/audio-packs/" \
        --progress --transfers "$TRANSFERS" --retries 5 --low-level-retries 10 \
        --s3-no-check-bucket
else
    echo "Skipping: export/audio-packs/ not found" >&2
fi

echo "=== Uploading dictionary database ==="
DB_FILE="${DB_FILE:-oald10.db}"
if [[ ! -f "$DB_FILE" ]]; then
    echo "Error: $DB_FILE not found. Run: python build_db.py" >&2
    exit 1
fi
rclone copyto "$DB_FILE" "${REMOTE}:${BUCKET}/db/oald10.db" \
    --progress --retries 5 --low-level-retries 10 \
    --s3-no-check-bucket

echo ""
echo "=== Verifying ==="
rclone size "${REMOTE}:${BUCKET}/"

echo ""
echo "Done. Enable public access: Cloudflare dashboard > R2 > oald10 > Settings"
