#!/bin/bash

# Wave Farm Mac System Audit Script
# Outputs markdown-ready documentation with real-time terminal feedback

TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
HOSTNAME=$(hostname -s)
OUTPUT_FILE="mac_audit_${HOSTNAME}_$(date +%Y%m%d_%H%M%S).md"

# Use tee to output to both terminal and file
exec > >(tee "$OUTPUT_FILE")

echo "════════════════════════════════════════════════"
echo "  Wave Farm Mac Audit - $HOSTNAME"
echo "  Started: $(date)"
echo "════════════════════════════════════════════════"
echo ""

cat << EOF
# Wave Farm Mac System Audit

**Computer:** $HOSTNAME  
**Date:** $TIMESTAMP  
**Serial:** $(system_profiler SPHardwareDataType | awk '/Serial/ {print $4}')

---

## System Information

### macOS Version
EOF

sw_vers | sed 's/^/- /'

cat << EOF

### Hardware
EOF

system_profiler SPHardwareDataType | grep -E "Model Name|Model Identifier|Chip|Processor|Number of Cores|Memory:" | sed 's/^      /- /'

MODEL_ID=$(system_profiler SPHardwareDataType | awk '/Model Identifier/ {print $3}')
echo ""
echo "**Model ID:** $MODEL_ID"

cat << EOF

---

## Memory (RAM)

### Capacity & Type
EOF

system_profiler SPMemoryDataType | grep -E "^\s*(Size|Type|Speed|Status|Manufacturer)" | head -20 | sed 's/^      /- /'

echo ""
echo "### Current Usage"
memory_pressure 2>/dev/null | grep "System-wide memory free percentage" | sed 's/^/- /' || echo "- Unable to determine"

cat << EOF

---

## Storage

### Disk Usage
EOF

TOTAL=$(df -h / | tail -1 | awk '{print $2}')
USED=$(df -h / | tail -1 | awk '{print $3}')
AVAIL=$(df -h / | tail -1 | awk '{print $4}')
PERCENT=$(df -h / | tail -1 | awk '{print $5}')

cat << EOF

| Metric | Value |
|--------|-------|
| Total Capacity | $TOTAL |
| Space Used | $USED |
| Space Available | $AVAIL |
| Percentage Full | $PERCENT |

EOF

# Health status
SMART=$(diskutil info / | grep "SMART Status" | awk '{print $3}')
DRIVE_TYPE=$(diskutil info / | grep "Solid State" | awk '{print $3}')

echo "**SMART Status:** $SMART"
echo "**Drive Type:** ${DRIVE_TYPE:-HDD}"

cat << EOF

---

## Time Machine Backup

EOF

if tmutil version &>/dev/null; then
    echo "### Backup Status"
    echo ""
    
    LATEST=$(tmutil latestbackup 2>/dev/null)
    if [ -n "$LATEST" ]; then
        BACKUP_DATE=$(echo "$LATEST" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}' | sed 's/\([0-9]\{4\}\)-\([0-9]\{2\}\)-\([0-9]\{2\}\)-\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3 \4:\5:\6/')
        echo "- **Last Backup:** $BACKUP_DATE"
        
        # Days since backup
        if [[ "$OSTYPE" == "darwin"* ]]; then
            BACKUP_EPOCH=$(echo "$LATEST" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | xargs -I {} date -j -f "%Y-%m-%d" {} "+%s" 2>/dev/null)
            NOW_EPOCH=$(date "+%s")
            if [ -n "$BACKUP_EPOCH" ]; then
                DAYS_AGO=$(( (NOW_EPOCH - BACKUP_EPOCH) / 86400 ))
                echo "- **Days Since Backup:** $DAYS_AGO"
            fi
        fi
    else
        echo "- **Status:** ⚠️ No backups found"
    fi
    
    echo ""
    echo "### Destinations"
    echo ""
    tmutil destinationinfo 2>/dev/null | grep -E "Name|Kind|Mount Point|ID" | sed 's/^/- /'
else
    echo "⚠️ Time Machine not available"
fi

cat << EOF

---

## Software Updates

### Update Status
EOF

echo ""
echo "🔍 Checking for updates (this may take 10-15 seconds)..."
softwareupdate -l 2>&1 > /tmp/sw_update.txt

if grep -q "No new software available" /tmp/sw_update.txt; then
    echo "✓ System is up to date"
else
    echo ""
    echo "**Available Updates:**"
    echo '```'
    cat /tmp/sw_update.txt | grep -v "^$" | grep -v "Software Update Tool"
    echo '```'
fi

rm -f /tmp/sw_update.txt

echo ""
echo "### Recent Install History"
echo ""
system_profiler SPInstallHistoryDataType | head -30 | sed 's/^      /    /'

cat << EOF

---

## Installed Applications

### Key Applications
EOF

echo ""
echo '```'
system_profiler SPApplicationsDataType | grep -B 1 "Location: /Applications" | grep -E "Location:|Version:" | head -60
echo '```'

if command -v brew &>/dev/null; then
    echo ""
    echo "### Homebrew Packages (Top 30)"
    echo ""
    echo '```'
    brew list --versions 2>/dev/null | head -30
    echo '```'
fi

cat << EOF

---

## System Health

### Uptime
EOF

echo ""
uptime | sed 's/^/- /'

echo ""
echo "### Kernel Panics (Last 30 Days)"
echo ""

# Check actual panic report files (INSTANT vs 60-90 seconds)
PANIC_FILES=$(find /Library/Logs/DiagnosticReports -name "*.panic" -mtime -30 2>/dev/null)

if [ -z "$PANIC_FILES" ]; then
    echo "- ✓ No panic reports found"
else
    PANIC_COUNT=$(echo "$PANIC_FILES" | wc -l | tr -d ' ')
    echo "- ⚠️ **$PANIC_COUNT panic report(s) found**"
    echo ""
    
    # Show recent panic files
    echo "**Recent panic reports:**"
    echo '```'
    ls -lth /Library/Logs/DiagnosticReports/*.panic 2>/dev/null | head -5
    echo '```'
    
    # Extract the panic string from most recent
    LATEST_PANIC=$(ls -t /Library/Logs/DiagnosticReports/*.panic 2>/dev/null | head -1)
    if [ -n "$LATEST_PANIC" ]; then
        echo ""
        echo "**Most recent panic cause:**"
        echo '```'
        grep -A 2 "^panic(cpu" "$LATEST_PANIC" 2>/dev/null | head -5 || echo "Unable to extract panic string"
        echo '```'
    fi
fi

# Battery for laptops
BATTERY_INFO=$(system_profiler SPPowerDataType | grep -E "Cycle Count|Condition")
if [ -n "$BATTERY_INFO" ]; then
    echo ""
    echo "### Battery Health"
    echo ""
    echo "$BATTERY_INFO" | sed 's/^      /- /'
fi

cat << EOF

---

## Network & Security

### Network Interfaces
EOF

echo ""
echo '```'
ifconfig | grep -E "^[a-z]|inet " | head -20
echo '```'

echo ""
echo "### FileVault Status"
echo ""
fdesetup status | sed 's/^/- /'

echo ""
echo "### Firewall Status"
echo ""
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | sed 's/^/- /' || echo "- Unable to determine (requires sudo)"

cat << EOF

---

## User Accounts

### Local Users

EOF

dscl . list /Users | grep -v "^_" | sed 's/^/- /'

cat << EOF

---

## Summary

✓ Audit completed: $(date)  
✓ Report saved to: \`$OUTPUT_FILE\`

### Action Items

EOF

# Generate action items based on findings
PERCENT_NUM=${PERCENT%\%}
if [ "$PERCENT_NUM" -gt 80 ]; then
    echo "- [ ] **Storage:** Disk is ${PERCENT} full - cleanup needed"
fi

if [ -z "$LATEST" ]; then
    echo "- [ ] **Backup:** Configure Time Machine backup"
elif [ "${DAYS_AGO:-999}" -gt 7 ]; then
    echo "- [ ] **Backup:** Last backup was ${DAYS_AGO} days ago"
fi

if [ -f /tmp/sw_update.txt ] && grep -q "recommended" /tmp/sw_update.txt 2>/dev/null; then
    echo "- [ ] **Updates:** Software updates available"
fi

echo ""
echo "---"
echo "*Generated by Wave Farm Mac Audit Script*"
echo ""
echo "════════════════════════════════════════════════"
echo "✓ Report complete: $OUTPUT_FILE"
echo "════════════════════════════════════════════════"
