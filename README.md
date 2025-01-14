## README.md
## Build Kali NetHunter for Google Pixel 4 (codename: *flame*)

**Author**: capslock303
**Version**: 1.0  
**Date**: 2025-01-14  

## Overview

This repository (or folder) contains a single script, [`build_nethunter_flame.sh`](./build_nethunter_flame.sh), which automates:

1. **Cloning** the Google Pixel 4 kernel source (from the LineageOS `msm-4.14` repository).  
2. **Fetching** a smaller/stable Clang toolchain from Google’s AOSP prebuilt archives.  
3. **Applying** all Kali NetHunter-related kernel configurations (HID gadget, netfilter, Wi-Fi injection, etc.).  
4. **Building** the custom kernel with the correct cross-compiler.  
5. **Packaging** the newly built kernel with [AnyKernel3](https://github.com/osm0sis/AnyKernel3) into a standalone flashable `.zip`.  
6. **Downloading** the **full** NetHunter rootfs (for arm64) and **building** a complete NetHunter installer ZIP via the official Kali NetHunter build scripts.  

After running it, you will have:

1. A **standalone kernel** `.zip` for Pixel 4 (*flame*).  
2. A **full** NetHunter installer `.zip` (includes kernel + rootfs + NetHunter environment), which you can flash in TWRP or another custom recovery.

---

## Prerequisites

- A **Debian/Kali-based** Linux environment. This script is tested on **Kali Linux 2024.4** (or later).  
- **Unlocked bootloader** on your Pixel 4.  
- **Rooted** device (if you plan to retain Magisk after flashing; otherwise root is optional).  
- At least **20–30 GB** of free disk space.  
- A **stable internet connection** (to download the source code, toolchains, and NetHunter rootfs).  

---

## Usage

1. **Download or clone** this repository (or just the script).  
2. Make sure the script is executable:  
   ```bash
   chmod +x build_nethunter_flame.sh
