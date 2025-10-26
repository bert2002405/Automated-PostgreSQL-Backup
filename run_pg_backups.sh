
echo "PostgreSQL backup script running..."


#!/bin/bash
set -e
set -o pipefail

# ----------------------------
# Configuration Variables
# ----------------------------
DB_NAME="production_db"
BACKUP_DIR="/home/velasco-albert/Laboratory Exercises/Lab8"
LOG_FILE="/var/log/pg_backup.log"
EMAIL="velasco.albert@gmai.com"
RCLONE_REMOTE="gdrive_backups:"
RETENTION_DAYS=7

# PostgreSQL credentials (set in environment or use .pgpass)
PG_USER="postgres"
PG_HOST="localhost"

# Initialize status
BACKUP_FAILED=0

# Logging function
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

exec >>"$LOG_FILE" 2>&1
log_message "Starting PostgreSQL backup script..."


# ----------------------------
# 3. Task 1: Full Logical Backup
# ----------------------------
LOGICAL_BACKUP_FILE="$BACKUP_DIR/${DB_NAME}_$(date '+%Y-%m-%d-%H%M%S').dump"
log_message "Starting full logical backup: $LOGICAL_BACKUP_FILE"

if pg_dump -U "$PG_USER" -h "$PG_HOST" -Fc "$DB_NAME" -f "$LOGICAL_BACKUP_FILE"; then
    log_message "Logical backup completed successfully."
else
    log_message "Logical backup failed!"
    BACKUP_FAILED=1
fi

# ----------------------------
# 3. Task 2: Physical Base Backup
# ----------------------------
PHYSICAL_BACKUP_FILE="$BACKUP_DIR/pg_base_backup_$(date '+%Y-%m-%d-%H%M%S').tar.gz"
log_message "Starting physical base backup: $PHYSICAL_BACKUP_FILE"

if pg_basebackup -U "$PG_USER" -h "$PG_HOST" -Ft -Z 9 -D - | gzip > "$PHYSICAL_BACKUP_FILE"; then
    log_message "Physical backup completed successfully."
else
    log_message "Physical backup failed!"
    BACKUP_FAILED=1
fi

# ----------------------------
# 4. Error Handling & Email Notification
# ----------------------------
send_email() {
    SUBJECT="$1"
    BODY="$2"
    echo -e "$BODY" | mail -s "$SUBJECT" "$EMAIL"
}

if [[ $BACKUP_FAILED -eq 1 ]]; then
    log_message "Backup failed. Sending failure email....
    LAST_LOG=$(tail -n 15 "$LOG_FILE")
    send_email "FAILURE: PostgreSQL Backup Task" "Backup task failed.\n\n$LAST_LOG"
    exit 1
fi

# ----------------------------
# 5. Cloud Upload
# ----------------------------
log_message "Uploading backups to Google Drive..."
if rclone copy "$LOGICAL_BACKUP_FILE" "$PHYSICAL_BACKUP_FILE" "$RCLONE_REMOTE"; then
    log_message "Upload successful."
    send_email "SUCCESS: PostgreSQL Backup and Upload" \
        "Successfully created and uploaded:\n$LOGICAL_BACKUP_FILE\n$PHYSICAL_BACKUP_FILE"
else
    log_message "Upload failed!"
    send_email "FAILURE: PostgreSQL Backup Upload" \
        "Backups were created locally but failed to upload to Google Drive. Check rclone logs."
    exit 1
fi

# ----------------------------
# 6. Local Cleanup
# ----------------------------
log_message "Cleaning up local backups older than $RETENTION_DAYS days..."
find "$BACKUP_DIR" -type f -name "*.dump" -mtime +$RETENTION_DAYS -exec rm -f {} \;
find "$BACKUP_DIR" -type f -name "*.tar.gz" -mtime +$RETENTION_DAYS -exec rm -f {} \;

log_message "=== PostgreSQL backup script completed successfully ==="
