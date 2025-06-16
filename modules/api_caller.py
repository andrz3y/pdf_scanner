#!/usr/bin/env python3
#
# ************************
# PDFSEC        api_caller 
# ************************
# version:          1.801
# *******************************************************************
# This script uses free API connections to VIRUSTOTAL.com & KASPERSKY
# *******************************************************************
#
import os
import time
import requests
from pathlib import Path
from datetime import datetime
import json
import sys
#
# ─────────── RELATIVE TO THE SCRIPT PATHS ─────────────
SCRIPT_DIR = Path(__file__).resolve().parent.parent
LOG_FILE = SCRIPT_DIR / "logs" / "pdfsec.log"
DOWNLOADS_DIR = Path.home() / "Downloads"
SANITIZED_DIR = SCRIPT_DIR / "sanitizer" / "sanitized"

# API KEYS (replace XXXX with API keys)
VT_UPLOAD_URL = "https://www.virustotal.com/api/v3/files"
VT_ANALYSIS_URL = "https://www.virustotal.com/api/v3/analyses"
VT_API_KEY = "XXXX"
KASPERSKY_SCAN_URL = "https://opentip.kaspersky.com/api/v1/scan/file"
KASPERSKY_RESULT_URL = "https://opentip.kaspersky.com/api/v1/getresult/file"
KASPERSKY_API_KEY = "XXXX"

# ────────────── LOGGING ──────────────
def timestamp():
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")

def write_log(module, message):
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(LOG_FILE, "a") as lf:
        lf.write(f"{timestamp()} | {module} | {message}\n")

# ────────────── PDF FINDER ──────────────
def list_pdfs():
    files = sorted(DOWNLOADS_DIR.glob("*.pdf"))
    if SANITIZED_DIR.exists():
        files += sorted(SANITIZED_DIR.glob("*.pdf"))
    return files

def human_readable_size(num_bytes):
    for unit in ['B','KB','MB','GB','TB']:
        if num_bytes < 1024.0 or unit == 'TB':
            return f"{num_bytes:.1f} {unit}"
        num_bytes /= 1024.0

def choose_pdf(pdf_list):
    print("\nAvailable PDFs:\n")
    for idx, p in enumerate(pdf_list, start=1):
        size = human_readable_size(p.stat().st_size)
        print(f"  {idx}) {p.name}  ({size})")
    print()
    while True:
        choice = input(f"Enter number (1–{len(pdf_list)}) or 'q' to cancel: ").strip()
        if choice.lower() == "q":
            return None
        if choice.isdigit() and 1 <= int(choice) <= len(pdf_list):
            return pdf_list[int(choice) - 1]
        print("  → Invalid selection, try again.")

# ─────────── VIRUSTOTAL ───────────
def upload_to_virustotal(pdf_path, api_key):
    headers = {"accept": "application/json", "x-apikey": api_key}
    with open(pdf_path, "rb") as f:
        files = {"file": (pdf_path.name, f, "application/pdf")}
        resp = requests.post(VT_UPLOAD_URL, headers=headers, files=files)
    if resp.status_code not in (200, 201):
        raise RuntimeError(f"VT upload failed (HTTP {resp.status_code}): {resp.text}")
    data = resp.json().get("data", {})
    return data.get("id")

def poll_analysis(analysis_id, api_key):
    headers = {"accept": "application/json", "x-apikey": api_key}
    url = f"{VT_ANALYSIS_URL}/{analysis_id}"
    while True:
        resp = requests.get(url, headers=headers)
        if resp.status_code != 200:
            raise RuntimeError(f"VT polling error (HTTP {resp.status_code}): {resp.text}")
        attrs = resp.json().get("data", {}).get("attributes", {})
        if attrs.get("status", "").lower() == "completed":
            return attrs.get("stats", {})
        print("  • Still scanning VirusTotal… sleeping 5 sec")
        time.sleep(5)

# ─────────── KASPERSKY ───────────
def upload_to_kaspersky(pdf_path, api_key):
    url = f"{KASPERSKY_SCAN_URL}?filename={pdf_path.name}"
    headers = {
        "x-api-key": api_key,
        "Content-Type": "application/octet-stream"
    }
    with open(pdf_path, "rb") as f:
        resp = requests.post(url, headers=headers, data=f)
    if resp.status_code != 200:
        raise RuntimeError(f"Kaspersky upload failed (HTTP {resp.status_code}): {resp.text}")
    return resp.json()

def poll_kaspersky(file_hash, api_key):
    url = f"{KASPERSKY_RESULT_URL}?request={file_hash}"
    headers = {"x-api-key": api_key}
    while True:
        resp = requests.post(url, headers=headers)
        if resp.status_code != 200:
            raise RuntimeError(f"Kaspersky polling error (HTTP {resp.status_code}): {resp.text}")
        data = resp.json()
        status = data.get("FileStatus", "").lower()
        if status == "complete":
            return data
        print("  • Still scanning Kaspersky… sleeping 5 sec")
        time.sleep(5)

# ─────────── MAIN FUNCTION ───────────
def main():
    pdfs = list_pdfs()
    if not pdfs:
        print("No PDFs found in downloads or sanitized.")
        return

    chosen = choose_pdf(pdfs)
    if chosen is None:
        print("Cancelled.")
        return

    print(f"\nSelected: {chosen}\n")
    write_log("api_caller", f"Chosen {chosen.name}")

    vt_key = VT_API_KEY.strip()
    if not vt_key:
        print("Error: no VirusTotal API key configured; aborting.")
        write_log("api_caller", "No VT API key provided.")
        return

    # VirusTotal
    try:
        print("Uploading to VirusTotal…")
        write_log("api_caller", f"Uploading {chosen.name} to VT")
        analysis_id = upload_to_virustotal(chosen, vt_key)
        if not analysis_id:
            raise RuntimeError("No analysis_id returned from VT.")
        print(f"Upload accepted by VT, analysis ID = {analysis_id}\n")
        write_log("api_caller", f"Received VT analysis_id={analysis_id}")
        print("Polling VirusTotal (may take ~20–30 sec)…")
        vt_stats = poll_analysis(analysis_id, vt_key)
    except Exception as e:
        print(f"Error (VirusTotal): {e}")
        write_log("api_caller", f"Error during VT upload/poll: {e}")
        vt_stats = None

    # Kaspersky
    kasp_key = KASPERSKY_API_KEY.strip()
    if not kasp_key:
        print("Error: no Kaspersky API key configured; skipping Kaspersky scan.")
        write_log("api_caller", "No Kaspersky API key provided.")
        kasp_stats = None
    else:
        try:
            print("Uploading to Kaspersky…")
            write_log("api_caller", f"Uploading {chosen.name} to Kaspersky")
            kasp_data = upload_to_kaspersky(chosen, kasp_key)
            write_log("api_caller", f"Kaspersky basic response: {json.dumps(kasp_data)}")

            status = kasp_data.get("FileStatus", "").lower()
            if status != "complete":
                file_info = kasp_data.get("FileGeneralInfo", {})
                file_hash = file_info.get("SHA256") or file_info.get("SHA1") or file_info.get("MD5")
                if not file_hash:
                    raise RuntimeError("Cannot retrieve file hash from Kaspersky basic response.")
                print(f"Kaspersky returned status '{status.upper()}', polling for completion…")
                kasp_data = poll_kaspersky(file_hash, kasp_key)
                write_log("api_caller", f"Kaspersky final response: {json.dumps(kasp_data)}")

            kasp_stats = kasp_data
        except Exception as e:
            print(f"Error (Kaspersky): {e}")
            write_log("api_caller", f"Error during Kaspersky upload/poll: {e}")
            kasp_stats = None

    # VirusTotal results  
    if vt_stats is not None:
        harmless   = vt_stats.get("harmless", 0)
        malicious  = vt_stats.get("malicious", 0)
        suspicious = vt_stats.get("suspicious", 0)
        undetected = vt_stats.get("undetected", 0)

        print("\nVirusTotal Results:")
        print(f"  • Harmless   : {harmless}")
        print(f"  • Malicious  : {malicious}")
        print(f"  • Suspicious : {suspicious}")
        print(f"  • Undetected : {undetected}\n")

        verdict = "MALICIOUS" if malicious > 0 else "CLEAN"
        color = "\033[31m" if malicious > 0 else "\033[32m"
        print(f"→ VT VERDICT: {color}{verdict}\033[0m\n")

        log_msg = (
            f"{chosen.name} → VT harmless={harmless}, malicious={malicious}, "
            f"suspicious={suspicious}, undetected={undetected}"
        )
        write_log("vt_api", log_msg)

    # Kaspersky results 
    if kasp_stats is not None:
        zone = kasp_stats.get("Zone", "<unknown>")
        file_status = kasp_stats.get("FileStatus", "<unknown>")
        general_info = kasp_stats.get("FileGeneralInfo", {})

        print("Kaspersky Results:")
        print(f"  • Zone       : {zone}")
        print(f"  • Status     : {file_status}")
        md5    = general_info.get("MD5")
        sha1   = general_info.get("SHA1")
        sha256 = general_info.get("SHA256")
        size   = general_info.get("Size")
        ftype  = general_info.get("Type")

        if md5:
            print(f"  • MD5        : {md5}")
        if sha1:
            print(f"  • SHA1       : {sha1}")
        if sha256:
            print(f"  • SHA256     : {sha256}")
        if size:
            print(f"  • Size       : {size}")
        if ftype:
            print(f"  • File Type  : {ftype}")
        print()

        if zone.lower() == "red":
            verdict2 = "MALICIOUS"
        elif zone.lower() == "yellow":
            verdict2 = "POTENTIALLY UNWANTED"
        elif zone.lower() == "green":
            verdict2 = "CLEAN"
        else:
            verdict2 = "UNKNOWN"

        color2 = "\033[31m" if verdict2 in ("MALICIOUS", "POTENTIALLY UNWANTED") else "\033[32m"
        print(f"→ Kaspersky VERDICT: {color2}{verdict2}\033[0m\n")

        write_log("kaspersky_api", json.dumps(kasp_stats))

    print(f"Results logged to {LOG_FILE}")

if __name__ == "__main__":
    main()
