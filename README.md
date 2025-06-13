# PDFSec 

PDFSec written to check safery of PDF files downloaded from, well, anywhere. 

I do have dedicated download VM but if moving PDFs to any other machine I always check them for security reasons...


# First Run 

Before first run API keys are required for : 
- `https://www.virustotal.com/api/v3/analyses` as: `VT_API_KEY`
- `https://opentip.kaspersky.com/api/v1/scan/file` as `KASPERSKY_API_KEY`


Scribt written for Ubuntu, so download zipped project, run bootstrap script: `sudo bash bootstrap.sh`. 

Bash Menu script provides following options: 

 

```bash 
0) Install/Check Prerequisites                  # quickly checks if prerequstes are installed, creates venv and installs them if necessary 
1) Quick scan all PDFs in Downloads             # ubuntu based bash script utilizing ClamAV, pdftotext, exiftool
2) Detailed PDF-parser wrapper                  # utilizing DidierStevens pdf_parser script looking for “suspicious” keywords to search for in streams
3) Sanitize a PDF (rasterize pages)             # moves suspicious PDF to sanitized folder 
4) API caller (virustotal + tylabs)             # uses free API (account required) from virutotal and tylabs, to upload and check PDF 
5) Paranoid‐mode: open PDF in firejain sandbox  # with live network and OS monitoring + pcap capture and basic analysis 
```


All results and status messages are logged into singe logfile:

`~/pdfsec/logs/pdfsec.log`

Designed to be running on Ubuntu. 



# Project Dir: 

```bash 
~/pdfsec/
│
├── config
│   └── bootstrap.sh            # ubuntu prereqs installer 
├── logs
│   ├─ pdfsec.log               # master log 
│   └─ pcap/                    # PCAP captures (e.g. tcpdump)
│       └─ pcap_capture.pcap
│
├── modules
│   ├── api_caller.py           # VirusTotal, Kaspersky API caller 
│   ├── pdf-parser.py           # parser wrapper for DidierStevens Github's script 
│   ├── pdf_sanitizer.py        # Rasterize‐all‐pages and create new PDF  
│   └── quick_scan.py           # ClamAV, pdfgrep scanner 
├── paranoid_mode
├── quarantine
├── sanitizer
│   └── venv
│       ├── bin
│       ├── include
│       ├── lib
│       ├── lib64 -> lib
│       └── pyvenv.cfg
│
└── scan_menu.sh                # main menu
```

 