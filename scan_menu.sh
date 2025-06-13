# ***********************
# PDFSEC scan_menu script 
# ***********************
# version:          1.801
#
# ***********************
# PDFSec main menu - bash
#  
# 
# *********************** 
# 
#!/usr/bin/env bash
set -euo pipefail
#
# CONFIG 
#
VERSION="1.801"
LOG_DIR="${HOME}/pdfsec/logs"
LOG_FILE="${LOG_DIR}/pdfsec.log"
DOWNLOADS_DIR="${HOME}/Downloads"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOTSTR_SCRIPT="${SCRIPT_DIR}/config/bootstrap.sh"

#
# LOGGING 
#
# - unified timestamps 
write_log() {
    local WHEN
    WHEN=$(date '+%Y-%m-%d %H:%M:%S')
    local MODULE="$1"
    local MESSAGE="$2"
    echo "${WHEN} | ${MODULE} | ${MESSAGE}" >> "${LOG_FILE}"
}

# 
# PRERECS CHECKER 
#
check_prereqs() {
    local missing=()

    # Define a small list of required commands/binaries.
    # If any is missing, collect it in “missing[]” for reporting.
    for cmd in clamscan pdfinfo pdfdetach pdfgrep qpdf firejail tcpdump auditctl python3; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    # Also check for “sanitizer/venv/bin/python” existence:
    if [[ ! -x "${SCRIPT_DIR}/sanitizer/venv/bin/python" ]]; then
        missing+=("sanitizer-venv")
    fi

    if (( ${#missing[@]} > 0 )); then
        echo
        echo "Missing prerequisites detected:"
        for m in "${missing[@]}"; do
            if [[ "$m" == "sanitizer-venv" ]]; then
                echo "  • sanitizer virtualenv (sanitizer/venv) not found"
            else
                echo "  • $m"
            fi
        done
        echo
        echo "Please run:"
        echo "    sudo bash \"${BOOTSTR_SCRIPT}\""
        echo "to install or configure all missing pieces."
        echo
        write_log "scan_menu" "Prereq check failed: missing ${missing[*]}"
        return 1
    fi

    write_log "scan_menu" "All prerequisites satisfied."
    return 0
}


#
# MAIN 
#
while true; do
    clear
    echo "───────────────────────────────────────"
    echo "  PDF Security Scanner v${VERSION}     "
    echo "───────────────────────────────────────"
    echo
    echo "Script version: ${VERSION}"
    echo "Current time: $(date '+%a %b %d %I:%M:%S %p %Z %Y')"
    echo
    echo "Choose an option:"
    echo "  0) Install/Check Prerequisites"
    echo "  1) Quick scan all PDFs in Downloads"
    echo "  2) Detailed PDF-parser wrapper"
    echo "  3) Sanitize a PDF (rasterize pages)"
    echo "  4) API caller (virustotal + tylabs + kaspersky)"
    echo "  5) Paranoid‐mode: promtp for snapshot + open PDF with live monitoring"
    echo "  q) Quit"
    echo
    read -rp "Selection: " choice

    case "${choice}" in
        0)
            clear
            echo
            echo "[0] Running prerequisites installer..."
            echo "------------------------------------------------"
            write_log "scan_menu" "Invoking prereqs check"
            sudo bash "${BOOTSTR_SCRIPT}"
            echo
            clear
            echo "Bootstrap Done. Returning to main menu."
            read -rp "Press Enter to continue…" _dummy
            ;;
        1)
            echo
            if ! check_prereqs; then
                echo "Aborting quick scan until prerequisites are installed."
                read -rp "Press Enter to return to main menu…" _dummy
                continue
            fi

            write_log "scan_menu" "Starting Quick scan"
            echo "      Starting quick scan of all PDFs in ${DOWNLOADS_DIR}…"
            echo

            # Call quick_scan module  
            "${SCRIPT_DIR}/modules/quick_scan.sh" 2>&1 | tee -a "${LOG_FILE}"

            write_log "scan_menu" "Quick scan completed"
            echo
            read -rp "Press Enter to return to main menu…" _dummy
            ;;
        2)
            echo
            if ! check_prereqs; then
                echo "Aborting wrapper run until prerequisites are installed."
                read -rp "Press Enter to return to main menu…" _dummy
                continue
            fi

            write_log "scan_menu" "Starting Detailed PDF-parser wrapper"
            echo "[*] Detailed PDF-parser wrapper will run on each PDF…"
            echo

            # Define the “suspicious” keywords to search for in streams
            KEYWORDS=(
              '/JavaScript'
              '/JS'
              '/EmbeddedFile'
              '/Launch'
              '/OpenAction'
              '/AA'
              '/RichMedia'
              '/URI'
            )

            for pdf in "${DOWNLOADS_DIR}"/*.pdf; do
                [[ -f "$pdf" ]] || continue
                echo "===== Wrapper on $(basename "$pdf") ====="
                echo "Working on: $pdf"
                write_log "pdf_parser" "Full dump of $pdf"

                # 1) Append full pdf-parser.py dump to the unified log
                python3 "${SCRIPT_DIR}/modules/pdf-parser.py" "$pdf" >> "${LOG_DIR}/pdfsec_parser.log" 2>&1

                # 2) Search each keyword via --searchstream
                found=()
                for kw in "${KEYWORDS[@]}"; do
                    # If any output is printed, that keyword exists in a stream
                    if python3 "${SCRIPT_DIR}/modules/pdf-parser.py" --searchstream "$kw" "$pdf" 2>/dev/null | grep -q .; then
                        found+=("$kw")
                    fi
                done

                # 3) Report on-screen verdict and log
                if (( ${#found[@]} > 0 )); then
                    IFS=',' read -r -a COMMA_JOIN <<< "${found[*]}"
                    echo -e "\e[31m [!!] UNSAFE: found ${COMMA_JOIN[*]}\e[0m"
                    write_log "pdf_parser" "$pdf → UNSAFE: ${COMMA_JOIN[*]}"
                else
                    echo "[+] SAFE: no suspicious keywords detected."
                    write_log "pdf_parser" "$pdf → SAFE"
                fi

                echo
                sleep 1
            done

            write_log "scan_menu" "Detailed wrapper run completed"
            read -rp "Press Enter to return to main menu…" _dummy
            ;;
        3)  
            echo
            if ! check_prereqs; then
                echo "Aborting sanitization until prerequisites are installed."
                read -rp "Press Enter to return to main menu…" _dummy
                continue
            fi

            write_log "scan_menu" "Starting sanitizer"
            echo "[*] Please enter the path of a single PDF you wish to sanitize, or press Enter to cancel:"
            read -rp "PDF path: " pdf_to_sanitize
            if [[ -z "$pdf_to_sanitize" || ! -f "$pdf_to_sanitize" ]]; then
                echo "No valid file given, cancelling."
                write_log "scan_menu" "Sanitization cancelled"
                read -rp "Press Enter to return to main menu…" _dummy
                continue
            fi

            # Call the sanitizer script inside its venv
            echo "Sanitizing $pdf_to_sanitize …"
            write_log "sanitizer" "Sanitizing $pdf_to_sanitize"
            (
              source "${SCRIPT_DIR}/sanitizer/venv/bin/activate"
              python3 "${SCRIPT_DIR}/sanitizer/pdf_sanitizer.py" "$pdf_to_sanitize"
            )
            write_log "sanitizer" "Finished sanitizing $pdf_to_sanitize"
            echo "Done. Sanitized PDF placed in your chosen output folder."
            read -rp "Press Enter to return to main menu…" _dummy
            ;;
        4)
            echo
            write_log "scan_menu" "Starting API caller mode"
            echo
            "${SCRIPT_DIR}/modules/api_caller.py"
            write_log "scan_menu" "API caller completed"
            read -rp "Press Enter to return to main menu…" _dummy
            ;;
        5)
            echo
            echo "==============================================="
            echo "!!! PARANOID MODE: DYNAMIC LIVE MONITORING !!!"
            echo "==============================================="
            echo "Before proceeding:"
            echo "  * Create a snapshot of your VM NOW (RECOMMENDED)."
            echo "  * If malware escapes, revert and DELETE the PDF."
            echo "  * This script will wait 60 seconds for snapshot."
            echo
            for ((i=60; i>0; i--)); do
                printf "\r  > Starting in %02d seconds... (Ctrl+C to abort)" "$i"
                sleep 1
            done
            echo
            read -rp "  Continue to Paranoid Mode? [Y/n] " continue_paranoid
            if [[ "${continue_paranoid,,}" =~ ^(n|no)$ ]]; then
                echo "Aborted by user."
                read -rp "Press Enter to return to main menu…" _dummy
                continue
            fi

            echo
            echo "The following apps may leak network traffic:"
            echo "  - brave-browser"
            echo "  - google-chrome"
            echo "  - firefox"
            echo "  - evince"
            echo "  - okular"
            echo "  - any open PDFs"
            echo
            ps -e | grep -E 'brave|chrome|firefox|evince|okular|acroread' >/tmp/ps_browsers.$$ || true
            if [ -s /tmp/ps_browsers.$$ ]; then
                echo "WARNING: Detected the following running browser/PDF viewer processes:"
                cat /tmp/ps_browsers.$$
                read -rp "Do you want to kill these automatically? [y/N] " kill_browsers
                if [[ "${kill_browsers,,}" =~ ^(y|yes)$ ]]; then
                    grep -Eo '^[ ]*[0-9]+' /tmp/ps_browsers.$$ | xargs --no-run-if-empty kill -9
                    echo "Killed detected browser/PDF processes."
                else
                    echo "Please manually close browsers/PDF viewers, then press Enter to continue."
                    read
                fi
            fi
            rm -f /tmp/ps_browsers.$$
            sleep 2

            echo
            echo "Select a PDF to open in Paranoid Mode:"
            PDF_DIR="${HOME}/Downloads"
            shopt -s nullglob
            pdf_files=("$PDF_DIR"/*.pdf)
            shopt -u nullglob
            if [ ${#pdf_files[@]} -eq 0 ]; then
                echo "No PDF files found in ${PDF_DIR}."
                read -rp "Press Enter to return to main menu…" _dummy
                continue
            fi
            select pdf_file in "${pdf_files[@]}"; do
                if [[ -n "$pdf_file" && -f "$pdf_file" ]]; then
                    break
                else
                    echo "Invalid selection. Try again."
                fi
            done

            pdf_base="$(basename "$pdf_file")"
            pdf_short="${pdf_base%.pdf}"
            session_ts="$(date +%Y%m%d_%H%M%S)"
            paranoid_dir="${HOME}/pdfsec/paranoid_mode/plogs___${pdf_short}_${session_ts}"
            mkdir -p "$paranoid_dir"

            write_log "scan_menu" "Paranoid-mode session starting for $pdf_base ($paranoid_dir)"

            # sudo prompt 
            echo "This mode requires root to capture network packets."
            sudo -v || { echo "Sudo credentials required. Aborting."; write_log "scan_menu" "Paranoid-mode aborted: no sudo"; read -rp "Press Enter to return to main menu…" _dummy; continue; }

            echo "Starting monitoring tools (tcpdump, inotifywait, process watcher)..."
            # tcpdump as root 
            sudo tcpdump -i any -w "$paranoid_dir/session.pcap" not port 22 >"$paranoid_dir/tcpdump.log" 2>&1 &
            tcpdump_pid=$!

            # Filesystem watcher as root 
            inotifywait -mr /home/"$USER" --exclude '^/home/' -o "$paranoid_dir/fs_changes.log" > /dev/null 2>&1 &
            inotify_pid=$!

            proc_snapshot_file="$paranoid_dir/proc_snapshot_${pdf_short}.log"
            (
                while true; do
                    echo "==== $(date '+%Y-%m-%d %H:%M:%S') ====" >> "$proc_snapshot_file"
                    ps -eo pid,ppid,cmd >> "$proc_snapshot_file"
                    echo >> "$proc_snapshot_file"
                    sleep 2
                done
            ) &
            procwatch_pid=$!

            # Open PDF in normal GUI (no firejail, just detonation with monitoring)
            echo
            echo "Opening $pdf_base in default PDF viewer. Please examine the file."
            echo "  (You have 30 seconds, or close the viewer when done)"
            xdg-open "$pdf_file" >/dev/null 2>&1 &

            # Wait for either 30 seconds, or for the viewer to close (best effort)
            for ((i=30; i>0; i--)); do
                sleep 1
                # If the PDF process is gone, break early (not 100% robust, but works for most viewers)
                if ! pgrep -f "$pdf_base" >/dev/null; then
                    break
                fi
            done

            # After closing PDF, keep monitoring for extra 15 seconds
            echo "PDF viewer closed. Continuing network monitoring for 15 seconds..."
            sleep 15

            echo "Stopping monitoring tools..."
            sudo kill "$tcpdump_pid" 2>/dev/null
            kill "$procwatch_pid" 2>/dev/null
            kill "$inotify_pid" 2>/dev/null

            # Wait a moment for output to flush
            sleep 1

            # Network summary: only if pcap was written
            if [[ -f "$paranoid_dir/session.pcap" ]]; then
                echo "Network connections detected during session:" | tee "$paranoid_dir/net_summary.txt"
                sudo tshark -r "$paranoid_dir/session.pcap" -q -z conv,tcp | tee -a "$paranoid_dir/net_summary.txt"
            else
                echo "No network packet capture (pcap) was saved."
            fi

            write_log "scan_menu" "Paranoid-mode monitoring stopped for $pdf_base"

            echo
            echo "Session logs and captures are in: $paranoid_dir"
            echo
            read -rp "Press Enter to return to main menu…" _dummy

            ;;



        q|Q)
            echo "Quitting."
            write_log "scan_menu" "User quit."
            exit 0
            ;;
        *)
            echo "Invalid option. Please choose 0,1,2,3,4 or q."
            read -rp "Press Enter to continue…" _dummy
            ;;
    esac
done
