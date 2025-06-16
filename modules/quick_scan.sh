#!/usr/bin/env bash
set -euo pipefail
# ************************ 
# PDFSEC    quick_scan.sh  
# ************************ 
# version:          1.801
# ************************ 

# All paths relative to repo root  
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOWNLOADS_DIR="${HOME}/Downloads"
LOG_DIR="${SCRIPT_DIR}/logs"
PDFSEC_DIR="${SCRIPT_DIR}"
SCAN_LOG="${LOG_DIR}/pdfsec.log"
QUARANTINE_DIR="${SCRIPT_DIR}/quarantine"
MODULE_NAME="quick_scan"

# Ensure log and quarantine directories exist
mkdir -p "${LOG_DIR}"
mkdir -p "${QUARANTINE_DIR}"
touch "${SCAN_LOG}"

# Date/time helper
timestamp() {
    date +'%Y-%m-%d %H:%M:%S'
}
#
# Logs 
#
# - append_to_log <component> <message>
append_to_log() {
    local component="$1"
    local message="$2"
    echo "$(timestamp) | ${component} | ${message}" >> "${SCAN_LOG}"
}

#
# ClamAV
# 
# - Update ClamAV Database
echo "Updating ClamAV database..."
append_to_log "${MODULE_NAME}" "Running freshclam to update ClamAV database"
if ! sudo freshclam --quiet; then
    append_to_log "${MODULE_NAME}" "freshclam update failed"
    echo "freshclam update failed, proceeding with existing DB"
else
    append_to_log "${MODULE_NAME}" "freshclam update succeeded"
fi
echo

#
# Scan 
#
scan_file() {
    local file="$1"
    local basename="$(basename "$file")"
    local risk=0
    local -a flags=()

    append_to_log "${MODULE_NAME}" "Starting scan of ${basename}"

    echo "------------------------------------------------------------------------------"
    echo "Scanning: ${basename}"
    echo "------------------------------------------------------------------------------"
    append_to_log "${MODULE_NAME}" "Scanning: ${basename}"

    # 1) Check if “file” thinks it's an executable/PE32, or ClamAV flags “FOUND”
    if file "$file" | grep -qiE 'executable|PE32|MS-DOS'; then
        risk=$((risk + 100))
        flags+=("Executable")
        append_to_log "${MODULE_NAME}" "file() reports Executable"
        echo "clamav: ▶ Skipped (detected as executable)"
    elif clamscan --no-summary "$file" 2>/dev/null | grep -q 'FOUND'; then
        risk=$((risk + 100))
        flags+=("VirusDetected")
        append_to_log "${MODULE_NAME}" "ClamAV: VirusDetected"
        echo "clamav: ▶ Virus Detected"
    else
        append_to_log "${MODULE_NAME}" "ClamAV: Clean"
        echo "clamav: ▶ No virus"
    fi

    # 2) Auto-trigger keywords via pdftotext → grep
    if pdftotext "$file" - 2>/dev/null | grep -qi '/JavaScript\|/OpenAction\|/AA'; then
        risk=$((risk + 50))
        flags+=("AutoTriggers")
        append_to_log "${MODULE_NAME}" "pdftotext: found auto-trigger keywords"
        echo "Auto‐triggers: ▶ keywords detected"
    else
        append_to_log "${MODULE_NAME}" "pdftotext: no auto-trigger keywords"
        echo "Auto‐triggers: ▶ none detected"
    fi

    # 3) Metadata: exiftool  
    if command -v exiftool >/dev/null 2>&1; then
        producer=$(exiftool -s -s -s -Producer "$file" 2>/dev/null || echo "")
        if [[ "$producer" =~ (calibre|mPDF|iText|A-PDF) ]]; then
            risk=$((risk + 30))
            flags+=("SuspiciousProducer")
            append_to_log "${MODULE_NAME}" "exiftool: SuspiciousProducer (${producer})"
            echo "exiftool: ▶ SuspiciousProducer (${producer})"
        else
            append_to_log "${MODULE_NAME}" "exiftool: Producer OK (${producer:-<none>})"
            echo "exiftool: ▶ Producer OK (${producer:-<none>})"
        fi
    else
        append_to_log "${MODULE_NAME}" "exiftool: NOT INSTALLED, skipping metadata check"
        echo "exiftool: ▶ NOT INSTALLED"
    fi

    # 4) Verify PDF structure: pdfinfo should succeed
    if ! pdfinfo "$file" &>/dev/null; then
        risk=$((risk + 20))
        flags+=("CorruptedPDF")
        append_to_log "${MODULE_NAME}" "pdfinfo: Corrupted or cannot parse"
        echo "pdfinfo: ▶ Corrupted or cannot parse"
    else
        append_to_log "${MODULE_NAME}" "pdfinfo: OK"
        echo "pdfinfo: ▶ OK"
    fi

    # 5) Password/encryption check via pev (if installed)
    if command -v pev >/dev/null 2>&1; then
        if pev "$file" 2>/dev/null | grep -q 'Encrypted: Yes'; then
            risk=$((risk + 10))
            flags+=("PasswordProtected")
            append_to_log "${MODULE_NAME}" "pev: Encrypted PDF"
            echo "pev: ▶ Encrypted PDF"
        else
            append_to_log "${MODULE_NAME}" "pev: Not encrypted"
            echo "pev: ▶ Not encrypted"
        fi
    else
        append_to_log "${MODULE_NAME}" "pev: NOT INSTALLED, skipping password check"
        echo "pev: ▶ NOT INSTALLED"
    fi

    # 6) pdfgrep for suspicious keywords (no “-E” option here)
    if pdfgrep -i -n '/JavaScript\|/JS\|/Launch\|/OpenAction\|/EmbeddedFile\|/AA\|/RichMedia\|/URI' "$file" &>/dev/null; then
        risk=$((risk + 50))
        flags+=("KeywordMatch")
        append_to_log "${MODULE_NAME}" "pdfgrep: Found suspicious keywords"
        echo "pdfgrep: ▶ Found suspicious keywords"
    else
        append_to_log "${MODULE_NAME}" "pdfgrep: no suspicious keywords"
        echo "pdfgrep: ▶ none detected"
    fi
    
    # Risk calculation 
    if (( risk >= 70 )); then
        echo -e "[🛑 MALICIOUS] ${file}    (risk=${risk})"
        echo "    FLAGS: ${flags[*]}"
        append_to_log "${MODULE_NAME}" "[MALICIOUS] ${file}, risk=${risk}, flags=${flags[*]}"
        # Move the malicious file to quarantine
        mv "$file" "${QUARANTINE_DIR}/"
        append_to_log "${MODULE_NAME}" "Moved ${basename} to quarantine"
    elif (( risk >= 30 )); then
        echo -e "[⚠️ WARNING ] ${file}    (risk=${risk})"
        echo "    FLAGS: ${flags[*]}"
        append_to_log "${MODULE_NAME}" "[WARNING] ${file}, risk=${risk}, flags=${flags[*]}"
    else
        echo -e "[✅ CLEAN   ] ${file}    (risk=${risk})"
        append_to_log "${MODULE_NAME}" "[CLEAN] ${file}, risk=${risk}"
    fi

    echo     
}

#
# MAIN 
#
echo "🔍 Starting quick scan of all PDFs in ${DOWNLOADS_DIR} …"
append_to_log "${MODULE_NAME}" "=== Quick scan started ==="

shopt -s nullglob
for file in "${DOWNLOADS_DIR}"/*.pdf; do
    [ -f "$file" ] || continue
    scan_file "$file"
done

echo "✅ Quick scan complete. Results appended to ${SCAN_LOG}"
append_to_log "${MODULE_NAME}" "=== Quick scan finished ==="
