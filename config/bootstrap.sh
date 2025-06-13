#!/usr/bin/env bash
set -euo pipefail
# ************************ 
# PDFSEC bootstrap script 
# ************************ 
# version:          1.701
# update date:      
# script location:  
# ************************ 

############## Configuration ##############
VERSION="1.701"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # <-- one level up from config/
MODULES_DIR="${SCRIPT_DIR}/modules"
SANITIZER_DIR="${SCRIPT_DIR}/sanitizer"
VENV_DIR="${SANITIZER_DIR}/venv"
LOG_DIR="${SCRIPT_DIR}/logs"
LOG_FILE="${LOG_DIR}/scan_log.txt"
DOWNLOADS_DIR="${SCRIPT_DIR}/downloads"
PREREQS_SCRIPT="${SCRIPT_DIR}/config/prereqscheck.sh"
############## Configuration-END ##############

# Figure out “real” (non-root) user & home
if [ -n "${SUDO_USER:-}" ]; then
  REAL_USER="${SUDO_USER}"
else
  REAL_USER="$(whoami)"
fi

#
# PHASE 1: Non-Root setup 
#
if [ "$EUID" -ne 0 ]; then
    echo "========================================"
    echo "  PDFsec bootstrap v${VERSION} (Phase 1)"
    echo "  Running as user: ${REAL_USER}"
    echo "========================================"
    echo

    # 1) Create directory structure in project folder
    echo "[P1-1] Creating base directories under project repo..."
    mkdir -p "${LOG_DIR}"
    mkdir -p "${SCRIPT_DIR}/quarantine"
    mkdir -p "${MODULES_DIR}"
    mkdir -p "${SANITIZER_DIR}"     # <--- ensure sanitizer exists
    mkdir -p "${SCRIPT_DIR}/paranoid_mode"
    mkdir -p "${DOWNLOADS_DIR}"     # Optional, so quick_scan works out of the box
    echo "  + Created: logs, quarantine, modules, sanitizer, paranoid_mode, downloads"
    echo

    # [P1-X] Make all scripts in modules/ executable
    echo "[P1-X] Making all scripts in modules/ executable..."
    find "${MODULES_DIR}" -type f \( -name "*.sh" -o -name "*.py" \) -exec chmod u+x {} \;
    echo "  + Set executable bit on all .sh and .py files in modules/"
    echo

    # 2) Download fresh pdf-parser.py into modules/
    echo "[P1-2] Downloading latest pdf-parser.py into modules/..."
    if [ ! -f "${MODULES_DIR}/pdf-parser.py" ]; then
        curl -sSL 'https://raw.githubusercontent.com/DidierStevens/DidierStevensSuite/master/pdf-parser.py' -o "${MODULES_DIR}/pdf-parser.py"
        chmod +x "${MODULES_DIR}/pdf-parser.py"
        echo "  + Downloaded and chmod +x: ${MODULES_DIR}/pdf-parser.py"
    else
        echo "  + pdf-parser.py already exists; skipping download."
    fi
    echo

    # 3) Ensure scan_menu.sh and wrappers are executable
    echo "[P1-3] Marking existing scripts executable..."
    if [ -f "${SCRIPT_DIR}/scan_menu.sh" ]; then
        chmod u+x "${SCRIPT_DIR}/scan_menu.sh"
        echo "  + chmod +x scan_menu.sh"
    fi
    if [ -f "${SANITIZER_DIR}/pdf_sanitizer.py" ]; then
        chmod u+x "${SANITIZER_DIR}/pdf_sanitizer.py"
        echo "  + chmod +x pdf_sanitizer.py"
    fi
    echo

    # 4) Ensure sanitizer dir and create Python3 venv under sanitizer/
    echo "[P1-4] Ensuring sanitizer dir exists and creating Python3 venv under sanitizer/..."
    mkdir -p "${SANITIZER_DIR}"                  # <-- ensure again, safe if exists
    python3 -m venv "${VENV_DIR}"
    echo "  + Virtualenv created at: ${VENV_DIR}"
    echo

    # 5) Activate venv and install Python packages
    echo "[P1-5] Activating venv and installing Python packages..."
    source "${VENV_DIR}/bin/activate"
    pip install --upgrade pip setuptools
    pip install PyMuPDF img2pdf Pillow peepdf
    deactivate
    echo "  + Installed: PyMuPDF, img2pdf, Pillow, peepdf"
    echo

    # 6) Phase 1 complete
    echo "========================================"
    echo "  Phase 1 complete. Structure and venv ready."
    echo "  Next: run this script as root: 'sudo bash $0' to install system packages."
    echo "========================================"
    exit 0
fi

#
# Phase 2: root actions (apt installs, etc.)
#

clear
echo "========================================"
echo "      PDFsec bootstrap v${VERSION}     "
echo "      Phase 2 (running as root)        "
echo "========================================"
echo

echo "[1] PDFsec - apt update"
echo
read -rp "  Would you like to run 'apt update' now? [Y/n] " answer
case "${answer,,}" in
  y|yes|'')
    echo "[2] PDFsec - apt update..."
    echo 
    apt update -y
    echo 
    echo "      update completed."
    ;;
  *)
    echo
    echo "[!] Skipping apt update, proceeding with installs."
    echo
    ;;
esac

# 2) Install core “C” tools
clear
echo
echo "[2] PDFsec - installing core tools..."
echo
apt install -y \
    clamav \
    clamav-daemon \
    poppler-utils \
    qpdf \
    pdfgrep \
    pev \
    tcpdump \
    auditd \
    firejail \
    libjpeg-dev \
    libmupdf-dev \
    yara \
    zlib1g-dev \
    inotify-tools

# 3) Install Python 3 + pip + venv components
clear
echo
echo "[3] PDFsec - installing python..."
echo
apt install -y \
    python3 \
    python3-venv \
    python3-pip \
    python3-requests \
    python3-yara

#
# 4) Sanity check: ensure user‐level directories and venv exist before exiting
#
clear
echo
echo "[4] PDFsec - verifying user‐level setup..."
echo
if [ -d "${VENV_DIR}" ]; then
    echo "   + Found existing venv at ${VENV_DIR}"
else
    echo "   [!] Warning: venv not found at ${VENV_DIR}"
fi
echo

# 5) Final message
clear
echo
echo "[5] PDFsec - bootstrap steps done. You can now run **scan_menu.sh** as your regular user."
echo "     - All system packages have been installed."
echo "     - Your venv and modules are already in place under ${SANITIZER_DIR}."
echo
exit 0
