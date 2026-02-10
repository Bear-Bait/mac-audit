#!/bin/bash

# Wave Farm Mac System Audit Script
# Outputs markdown-ready documentation with real-time terminal feedback
# Usage: mac-audit.sh [--md | --html | --both]

# --- Format selection ---
FORMAT="md"
case "${1:-}" in
    --html) FORMAT="html" ;;
    --both) FORMAT="both" ;;
    --md|"") FORMAT="md" ;;
    *)
        echo "Usage: $0 [--md | --html | --both]"
        echo "  --md    Markdown only (default)"
        echo "  --html  HTML only"
        echo "  --both  Both formats"
        exit 1
        ;;
esac

TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
HOSTNAME=$(hostname -s)
BASENAME="mac_audit_${HOSTNAME}_$(date +%Y%m%d_%H%M%S)"
OUTPUT_FILE="${BASENAME}.md"

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
    ls -lth /Library/Logs/DiagnosticReports/*.panic 2>/dev/null | head -5 || echo "Unable to list (permission denied)"
    echo '```'

    # Extract the panic string from most recent
    LATEST_PANIC=$(ls -t /Library/Logs/DiagnosticReports/*.panic 2>/dev/null | head -1)
    if [ -n "$LATEST_PANIC" ] && [ -r "$LATEST_PANIC" ]; then
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

### Network Configuration
EOF

echo ""

# Get all network services and report on active ones
while IFS= read -r SERVICE; do
    # Skip header line
    [[ "$SERVICE" == "An asterisk"* ]] && continue

    INFO=$(networksetup -getinfo "$SERVICE" 2>/dev/null)
    IP=$(echo "$INFO" | awk -F': ' '/^IP address/ {print $2}')

    # Skip services with no IP (not connected)
    [ -z "$IP" ] && continue

    SUBNET=$(echo "$INFO" | awk -F': ' '/^Subnet mask/ {print $2}')
    ROUTER=$(echo "$INFO" | awk -F': ' '/^Router/ {print $2}')
    DHCP_CHECK=$(echo "$INFO" | grep -c "DHCP Configuration")

    if [ "$DHCP_CHECK" -gt 0 ]; then
        IP_TYPE="DHCP (dynamic - may change)"
    else
        IP_TYPE="Manual (static)"
    fi

    echo "**$SERVICE**"
    echo ""
    echo "| Setting | Value |"
    echo "|---------|-------|"
    echo "| IP Address | \`$IP\` |"
    echo "| Subnet Mask | $SUBNET |"
    echo "| Router | $ROUTER |"
    echo "| IP Assignment | **$IP_TYPE** |"

    # Get MAC address for this interface
    HW_PORT=$(networksetup -listallhardwareports 2>/dev/null | grep -A 1 "$SERVICE" | awk '/Device/ {print $2}')
    if [ -n "$HW_PORT" ]; then
        MAC_ADDR=$(ifconfig "$HW_PORT" 2>/dev/null | awk '/ether/ {print $2}')
        [ -n "$MAC_ADDR" ] && echo "| MAC Address | \`$MAC_ADDR\` |"
    fi

    echo ""
done < <(networksetup -listallnetworkservices 2>/dev/null)

# DNS servers
echo "### DNS Servers"
echo ""
scutil --dns 2>/dev/null | awk '/nameserver\[/ {print $3}' | sort -u | while read -r DNS; do
    echo "- \`$DNS\`"
done
echo ""

# External IP (quick timeout so it doesn't hang)
echo "### External IP"
echo ""
EXT_IP=$(curl -s --max-time 5 ifconfig.me 2>/dev/null)
if [ -n "$EXT_IP" ]; then
    echo "- **Public IP:** \`$EXT_IP\`"
else
    echo "- Unable to determine (no internet or timeout)"
fi

echo ""
echo "### FileVault Status"
echo ""
fdesetup status 2>/dev/null | sed 's/^/- /' || echo "- Unable to determine (may require admin)"

echo ""
echo "### Firewall Status"
echo ""
/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | sed 's/^/- /' || echo "- Unable to determine (may require admin)"

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

# --- HTML conversion ---
if [ "$FORMAT" = "html" ] || [ "$FORMAT" = "both" ]; then

    HTML_FILE="${BASENAME}.html"

    convert_md_to_html() {
        local input="$1"
        local in_code=0
        local in_table=0

        cat << 'HTMLHEAD'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Wave Farm Mac Audit</title>
<style>
  body { font-family: "Courier New", "Roboto Slab", "Rockwell", Courier, monospace; max-width: 860px; margin: 2em auto; padding: 0 1em; color: #1d1d1f; line-height: 1.6; }
  h1 { border-bottom: 2px solid #0071e3; padding-bottom: 0.3em; }
  h2 { border-bottom: 1px solid #d2d2d7; padding-bottom: 0.2em; margin-top: 1.5em; }
  h3 { margin-top: 1.2em; }
  table { border-collapse: collapse; margin: 0.5em 0; width: 100%; }
  th, td { border: 1px solid #d2d2d7; padding: 6px 12px; text-align: left; }
  th { background: #f5f5f7; }
  pre { background: #f5f5f7; padding: 1em; border-radius: 6px; overflow-x: auto; }
  code { background: #f5f5f7; padding: 2px 6px; border-radius: 3px; font-size: 0.9em; }
  pre code { background: none; padding: 0; }
  hr { border: none; border-top: 1px solid #d2d2d7; margin: 1.5em 0; }
  ul { padding-left: 1.5em; }
  .checkbox { margin-right: 0.3em; }
  @media (prefers-color-scheme: dark) {
    body { background: #1d1d1f; color: #f5f5f7; }
    h1 { border-color: #2997ff; }
    h2, hr, th, td { border-color: #424245; }
    th, pre, code { background: #2c2c2e; }
  }
</style>
</head>
<body>
HTMLHEAD

        while IFS= read -r line; do
            # Code blocks
            if [[ "$line" == '```'* ]]; then
                if [ "$in_code" -eq 0 ]; then
                    in_code=1
                    echo "<pre><code>"
                else
                    in_code=0
                    echo "</code></pre>"
                fi
                continue
            fi
            if [ "$in_code" -eq 1 ]; then
                echo "$line" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
                continue
            fi

            # Horizontal rule
            if [[ "$line" == "---" ]]; then
                [ "$in_table" -eq 1 ] && { echo "</table>"; in_table=0; }
                echo "<hr>"
                continue
            fi

            # Table separator row (skip it, we already made <th>)
            if [[ "$line" =~ ^\|[-\|[:space:]]+\|$ ]]; then
                continue
            fi

            # Table rows
            if [[ "$line" == \|* ]]; then
                if [ "$in_table" -eq 0 ]; then
                    in_table=1
                    echo "<table>"
                    # First row is header
                    echo "<tr>"
                    echo "$line" | sed 's/^|//;s/|$//' | tr '|' '\n' | while IFS= read -r cell; do
                        cell=$(echo "$cell" | sed 's/^ *//;s/ *$//')
                        cell=$(echo "$cell" | sed 's/\*\*\([^*]*\)\*\*/<strong>\1<\/strong>/g; s/`\([^`]*\)`/<code>\1<\/code>/g')
                        echo "  <th>$cell</th>"
                    done
                    echo "</tr>"
                else
                    echo "<tr>"
                    echo "$line" | sed 's/^|//;s/|$//' | tr '|' '\n' | while IFS= read -r cell; do
                        cell=$(echo "$cell" | sed 's/^ *//;s/ *$//')
                        cell=$(echo "$cell" | sed 's/\*\*\([^*]*\)\*\*/<strong>\1<\/strong>/g; s/`\([^`]*\)`/<code>\1<\/code>/g')
                        echo "  <td>$cell</td>"
                    done
                    echo "</tr>"
                fi
                continue
            fi

            # Close table if we've left it
            if [ "$in_table" -eq 1 ]; then
                echo "</table>"
                in_table=0
            fi

            # Empty lines
            if [ -z "$line" ]; then
                continue
            fi

            # Headers
            if [[ "$line" == '### '* ]]; then
                echo "<h3>${line#\#\#\# }</h3>"
                continue
            fi
            if [[ "$line" == '## '* ]]; then
                echo "<h2>${line#\#\# }</h2>"
                continue
            fi
            if [[ "$line" == '# '* ]]; then
                echo "<h1>${line#\# }</h1>"
                continue
            fi

            # Checkbox list items
            if [[ "$line" == '- [ ] '* ]]; then
                content="${line#- \[ \] }"
                content=$(echo "$content" | sed 's/\*\*\([^*]*\)\*\*/<strong>\1<\/strong>/g; s/`\([^`]*\)`/<code>\1<\/code>/g')
                echo "<ul><li><span class=\"checkbox\">☐</span>$content</li></ul>"
                continue
            fi

            # List items
            if [[ "$line" == '- '* ]]; then
                content="${line#- }"
                content=$(echo "$content" | sed 's/\*\*\([^*]*\)\*\*/<strong>\1<\/strong>/g; s/`\([^`]*\)`/<code>\1<\/code>/g')
                echo "<ul><li>$content</li></ul>"
                continue
            fi

            # Italic line (single * wrapping, e.g. *text*)
            if [[ "$line" =~ ^\*[^*].*[^*]\*$ ]]; then
                inner="${line#\*}"
                inner="${inner%\*}"
                echo "<p><em>$inner</em></p>"
                continue
            fi

            # Regular paragraph with inline formatting
            formatted=$(echo "$line" | sed 's/\*\*\([^*]*\)\*\*/<strong>\1<\/strong>/g; s/`\([^`]*\)`/<code>\1<\/code>/g')
            echo "<p>$formatted</p>"

        done < "$input"

        [ "$in_table" -eq 1 ] && echo "</table>"

        echo "</body></html>"
    }

    # Wait for tee to flush
    sleep 1

    convert_md_to_html "$OUTPUT_FILE" > "$HTML_FILE"

    echo ""
    echo "════════════════════════════════════════════════"
    echo "✓ Reports complete:"
    if [ "$FORMAT" = "both" ]; then
        echo "  Markdown: $OUTPUT_FILE"
    fi
    echo "  HTML:     $HTML_FILE"
    echo "════════════════════════════════════════════════"

    # If HTML-only, remove the markdown file
    if [ "$FORMAT" = "html" ]; then
        rm -f "$OUTPUT_FILE"
    fi

else
    echo ""
    echo "════════════════════════════════════════════════"
    echo "✓ Report complete: $OUTPUT_FILE"
    echo "════════════════════════════════════════════════"
fi
