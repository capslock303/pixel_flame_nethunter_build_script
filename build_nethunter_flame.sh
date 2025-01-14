#!/usr/bin/env bash
###############################################################################
# Filename:  build_nethunter_flame.sh
# Author:    capslock303
# Date:      2025-01-14
#
# Description:
#   This script automates building a Kali NetHunter-compatible kernel for
#   Google Pixel 4 (flame) on Android 13. It uses a smaller, stable Clang
#   toolchain from Google's prebuilt archives and integrates the full
#   NetHunter rootfs. We forcibly set the device to "flame," enable all
#   NetHunter-related configs, and produce both a standalone kernel .zip
#   (AnyKernel3) and a full NetHunter installer .zip.
#
###############################################################################

set -e

###############################################################################
# 1. Install Dependencies
###############################################################################
echo "[*] Updating packages and installing dependencies..."
sudo apt-get update
sudo apt-get install -y \
    build-essential bc bison flex libssl-dev \
    ccache git zip unzip automake autoconf libncurses-dev \
    clang libclang-dev lld \
    python3 python3-pip wget curl sed grep cpio \
    liblz4-dev device-tree-compiler xz-utils

# NetHunter build script dependencies:
sudo apt-get install -y default-jdk python3-tqdm python3-pycryptodome

# Create a workspace
WORKDIR="${HOME}/nethunter_flame_build"
mkdir -p "${WORKDIR}"
cd "${WORKDIR}"

###############################################################################
# 2. Clone Kernel Source
###############################################################################
KERNEL_REPO="https://github.com/LineageOS/android_kernel_google_msm-4.14"
KERNEL_DIR="${WORKDIR}/kernel_flame"

if [ ! -d "${KERNEL_DIR}" ]; then
    echo "[*] Cloning kernel source from ${KERNEL_REPO}..."
    git clone --depth=1 "${KERNEL_REPO}" "${KERNEL_DIR}"
else
    echo "[*] Kernel source exists. Pulling latest changes..."
    cd "${KERNEL_DIR}"
    git pull
    cd "${WORKDIR}"
fi

###############################################################################
# 3. Clone AnyKernel3
###############################################################################
ANYKERNEL_REPO="https://github.com/osm0sis/AnyKernel3"
ANYKERNEL_DIR="${WORKDIR}/AnyKernel3"

if [ ! -d "${ANYKERNEL_DIR}" ]; then
    echo "[*] Cloning AnyKernel3..."
    git clone --depth=1 "${ANYKERNEL_REPO}" "${ANYKERNEL_DIR}"
else
    echo "[*] AnyKernel3 source exists. Pulling latest changes..."
    cd "${ANYKERNEL_DIR}"
    git pull
    cd "${WORKDIR}"
fi

###############################################################################
# 4. Clone Kali NetHunter Installer Scripts
###############################################################################
NH_INSTALLER_REPO="https://gitlab.com/kalilinux/nethunter/build-scripts/kali-nethunter-installer.git"
NH_INSTALLER_DIR="${WORKDIR}/kali-nethunter-installer"

if [ ! -d "${NH_INSTALLER_DIR}" ]; then
    echo "[*] Cloning Kali NetHunter installer scripts..."
    git clone "${NH_INSTALLER_REPO}" "${NH_INSTALLER_DIR}"
else
    echo "[*] NetHunter installer scripts exist. Pulling latest..."
    cd "${NH_INSTALLER_DIR}"
    git pull
    cd "${WORKDIR}"
fi

###############################################################################
# 5. Acquire Minimal Clang Toolchain (Smaller/Stable Release)
###############################################################################
# We'll fetch a stable release used by Pixel for Android 13: clang-r450784d
# Reference example: https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/tags/android-13.0.0_r30/clang-r450784d.tar.gz
# (Adjust if you need a different revision.)

TOOLCHAIN_VERSION="clang-r450784d"
TOOLCHAIN_ARCHIVE="clang-r450784d.tar.gz"
TOOLCHAIN_URL="https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/tags/android-13.0.0_r30/${TOOLCHAIN_VERSION}.tar.gz"

TOOLCHAIN_DIR="${WORKDIR}/clang_toolchain"
if [ ! -d "${TOOLCHAIN_DIR}" ]; then
    echo "[*] Downloading smaller Clang toolchain: ${TOOLCHAIN_VERSION}"
    wget -O "${TOOLCHAIN_ARCHIVE}" "${TOOLCHAIN_URL}"
    mkdir -p "${TOOLCHAIN_DIR}"
    tar -xzf "${TOOLCHAIN_ARCHIVE}" -C "${TOOLCHAIN_DIR}"
fi

# (Optional) Remove extraneous files from the toolchain to save space,
# but be careful not to remove needed binaries for cross-compilation.
echo "[*] (Optional) Minimizing toolchain directory..."
find "${TOOLCHAIN_DIR}" -type f -name '*.so' -not -path '*bin/*' -exec rm -f {} \; || true
# More advanced stripping steps could go here if desired.

# Export environment variables for cross compilation
export PATH="${TOOLCHAIN_DIR}/bin:${PATH}"
export ARCH=arm64
export SUBARCH=arm64
export CLANG_TRIPLE="aarch64-linux-gnu-"
export CROSS_COMPILE_COMPAT="arm-linux-gnueabi-"
export CROSS_COMPILE="aarch64-linux-android-"

###############################################################################
# 6. Kernel Configuration & Build
###############################################################################
cd "${KERNEL_DIR}"

echo "[*] Cleaning old build artifacts (mrproper)..."
make mrproper

# Check if there's a suitable flame_defconfig
DEFCONFIG="flame_defconfig"
if [ ! -f "arch/arm64/configs/${DEFCONFIG}" ]; then
    # Attempt other possibilities: coral_defconfig or vendor/flame_defconfig
    # Because Pixel 4 (flame) & Pixel 4 XL (coral) often share kernel trees.
    if [ -f "arch/arm64/configs/coral_defconfig" ]; then
        echo "[!] No flame_defconfig found. Copying coral_defconfig to flame_defconfig..."
        cp arch/arm64/configs/coral_defconfig arch/arm64/configs/flame_defconfig
        DEFCONFIG="flame_defconfig"
    elif [ -f "arch/arm64/configs/vendor/flame_defconfig" ]; then
        DEFCONFIG="vendor/flame_defconfig"
    else
        echo "[!] No flame_defconfig or coral_defconfig found. Creating new flame_defconfig from defconfig..."
        # Fallback: make defconfig from default and store as flame_defconfig
        make defconfig CC=clang LLVM=1
        cp .config arch/arm64/configs/flame_defconfig
        DEFCONFIG="flame_defconfig"
    fi
fi

echo "[*] Using defconfig: ${DEFCONFIG}"
make "${DEFCONFIG}" CC=clang LLVM=1

echo "[*] Enabling NetHunter HID gadget, netfilter, bridging, ebtables, VLAN, etc..."
if [ -f "scripts/config" ]; then
    # HID
    scripts/config --file .config --enable USB_HID
    scripts/config --file .config --enable USB_HIDDEV
    scripts/config --file .config --enable HID
    scripts/config --file .config --enable HID_GENERIC
    scripts/config --file .config --enable USB_GADGET
    scripts/config --file .config --enable USB_CONFIGFS_F_FS
    scripts/config --file .config --enable USB_CONFIGFS_F_HID
    scripts/config --file .config --enable INPUT_UINPUT

    # Wi-Fi injection / netfilter
    scripts/config --file .config --enable CFG80211
    scripts/config --file .config --enable MAC80211
    scripts/config --file .config --enable CFG80211_DEFAULT_PS
    scripts/config --file .config --enable BRIDGE
    scripts/config --file .config --enable VLAN_8021Q
    
    # Extended netfilter: NAT, iptables, ebtables, etc.
    scripts/config --file .config --enable NF_CONNTRACK
    scripts/config --file .config --enable NF_CONNTRACK_EVENTS
    scripts/config --file .config --enable NETFILTER_XT_MARK
    scripts/config --file .config --enable NETFILTER_XT_TARGET_MARK
    scripts/config --file .config --enable NF_NAT
    scripts/config --file .config --enable NF_TABLES
    scripts/config --file .config --enable IP_NF_IPTABLES
    scripts/config --file .config --enable IP_NF_MANGLE
    scripts/config --file .config --enable IP6_NF_MANGLE
    scripts/config --file .config --enable IP_NF_FILTER
    scripts/config --file .config --enable IP6_NF_FILTER
    scripts/config --file .config --enable IP6_NF_IPTABLES
    scripts/config --file .config --enable BRIDGE_NF_EBTABLES
    scripts/config --file .config --enable EBTABLES
    scripts/config --file .config --enable IP_SET
    scripts/config --file .config --enable IP_SET_HASH_IP
    scripts/config --file .config --enable IP_SET_HASH_NET

    # WireGuard
    scripts/config --file .config --enable WIREGUARD

    # Other recommended NetHunter features can be added here as needed...
else
    echo "[!] scripts/config not found. Opening menuconfig..."
    echo "    Enable HID gadget and netfilter manually, then exit + save."
    read -r
    make menuconfig CC=clang LLVM=1
fi

echo "[*] Finalizing .config with olddefconfig..."
make olddefconfig CC=clang LLVM=1

echo "[*] Building kernel... (this may take a while)"
make -j"$(nproc)" CC=clang LLVM=1

# Check for the compiled kernel image
KERNEL_IMAGE_PATH="arch/arm64/boot/Image.lz4-dtb"
if [ ! -f "${KERNEL_IMAGE_PATH}" ]; then
    echo "[!] Kernel image not found at ${KERNEL_IMAGE_PATH}. Searching..."
    find arch/arm64/boot -type f -name "Image*"
    echo "[!] Adjust KERNEL_IMAGE_PATH if needed. Exiting."
    exit 1
fi

###############################################################################
# 7. Prepare AnyKernel3 (Standalone Kernel Zip)
###############################################################################
cd "${ANYKERNEL_DIR}"

# Reset/clean AnyKernel3
git checkout . 2>/dev/null || true
git clean -fd 2>/dev/null || true

echo "[*] Copying compiled kernel Image.lz4-dtb..."
cp -f "${KERNEL_DIR}/${KERNEL_IMAGE_PATH}" "${ANYKERNEL_DIR}/Image.lz4-dtb"

echo "[*] Forcibly setting device name to 'flame' in anykernel.sh..."
sed -i 's/^device.name1=.*/device.name1=flame/' anykernel.sh
sed -i 's/^device.name2=.*/device.name2=flame/' anykernel.sh

# If you built extra modules, copy them into `modules/`.
# e.g.: cp -r "${KERNEL_DIR}/out_modules/lib/modules/*" modules/system/lib/modules

KERNEL_ZIP="Pixel4_NetHunterKernel_HID_$(date +%Y%m%d).zip"
echo "[*] Creating standalone kernel .zip: ${KERNEL_ZIP}..."
zip -r9 "${KERNEL_ZIP}" . -x ".git*" -x "README.md" -x "*.zip"

###############################################################################
# 8. Build Full NetHunter Flashable Zip (with Full Rootfs)
###############################################################################
cd "${WORKDIR}"

# Check the 2024.4 full rootfs naming from: https://kali.download/nethunter-images/current/
# Typically: kali-nethunter-2024.4-generic-arm64-rootfs-full.zip
ROOTFS_FILE="kali-nethunter-2024.4-generic-arm64-rootfs-full.zip"
if [ ! -f "${ROOTFS_FILE}" ]; then
    echo "[*] Downloading full NetHunter rootfs for arm64..."
    wget "https://kali.download/nethunter-images/current/${ROOTFS_FILE}"
fi

cd "${NH_INSTALLER_DIR}"
NH_OUT_ZIP="NetHunter_flame_full_$(date +%Y%m%d).zip"

echo "[*] Building full NetHunter flashable zip for flame..."
# The NetHunter build script usage can vary by version. We'll attempt:
./build.sh --device flame \
           --kernel "${ANYKERNEL_DIR}/${KERNEL_ZIP}" \
           --rootfs-file "${WORKDIR}/${ROOTFS_FILE}" \
           --output "${NH_OUT_ZIP}" \
           --force

echo "[*] Check output in ${NH_INSTALLER_DIR}/output or the current directory for: ${NH_OUT_ZIP}"

###############################################################################
# 9. Final Instructions
###############################################################################
cat <<EOF

========================================================================
  NetHunter Kernel & Full Image Build Complete for Google Pixel 4 (flame)
========================================================================

1) **Standalone Kernel Zip (AnyKernel3)**:
   - Location: ${ANYKERNEL_DIR}/${KERNEL_ZIP}
   - Flash in TWRP or another custom recovery if you only want the kernel.

2) **Full NetHunter Installer Zip (with rootfs + kernel)**:
   - Built by NetHunter build-scripts.
   - Check: ${NH_INSTALLER_DIR}/output/ or the current dir for ${NH_OUT_ZIP}
   - This is a complete package. Flash in TWRP to get NetHunter rootfs,
     apps, and the HID/netfilter-enabled kernel.

3) **Flashing Steps (Example)**:
   a. Transfer the .zip to device (adb push <zip> /sdcard/).
   b. Reboot to recovery: 'adb reboot recovery'
   c. In TWRP, choose 'Install' and select the .zip to flash.
   d. Re-flash Magisk if needed to retain root.
   e. Reboot system; NetHunter should be installed and HID/Injection should work.

4) **Verifications**:
   - Launch the NetHunter app. Test HID keyboard/caps lock, custom commands.
   - Check Wi-Fi injection, bridging, iptables, etc.

For any issues, confirm your defconfig is correct, ensure the correct 
rootfs file, and that your bootloader is unlocked.
========================================================================
EOF

exit 0
