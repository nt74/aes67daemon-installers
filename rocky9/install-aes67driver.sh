#!/usr/bin/env bash
# Script: install-aes67driver.sh
# Author: nikos.toutountzoglou@svt.se
# Description: AES67 Ravenna ALSA DKMS driver installation script for Rocky Linux 9.
# Revision: 1.6

set -euo pipefail

# --- Configuration ---
# Package details for the Ravenna ALSA driver
PKGNAME="ravenna-alsa-lkm"
PKGVER="1.15"
PKG_URL="https://github.com/bondagit/${PKGNAME}/archive/refs/tags/v${PKGVER}.tar.gz"
# MD5 checksum for the v1.15 tarball
PKG_MD5="149a9df6c7f5d6a5c01bf5e1b50a26f3"

# URL for the dkms.conf file
DKMS_CONF_URL="https://raw.githubusercontent.com/nt74/aes67daemon-installers/main/rocky9/dkms.conf"

# --- Style and Logging ---
# Colors for console output
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

# Logging functions for clear messaging
log_info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS] $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

log_error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
    exit 1
}

# --- Helper Functions ---

# Ensures the script is run with root privileges
check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        log_error "This script must be run as root or with sudo."
    fi
}

# Verifies that the operating system is Rocky Linux 9
check_distro() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        if [[ "${ID}" != "rocky" || "${VERSION_ID%%.*}" != "9" ]]; then
            log_error "This script is intended only for Rocky Linux 9."
        fi
        log_info "Rocky Linux 9 distribution confirmed."
    else
        log_error "Unable to detect the Linux distribution."
    fi
}

# Prompts the user for a yes/no confirmation
prompt_user() {
    local prompt_message="$1"
    while true; do
        read -r -p "$prompt_message (y/n) " response
        case "$response" in
            [Yy]* ) return 0;;
            [Nn]* ) return 1;;
            * ) echo "Please answer 'y' or 'n'." ;;
        esac
    done
}

# Installs all required packages and dependencies
install_dependencies() {
    log_info "Updating package repositories..."
    dnf makecache

    log_info "Enabling the CRB repository..."
    crb enable

    log_info "Installing required packages: Development Tools, EPEL, DKMS, and Kernel Headers..."
    dnf install -y epel-release
    dnf groupinstall -y "Development Tools"
    # Install headers for the currently running kernel
    dnf install -y dkms "kernel-headers-$(uname -r)"
}

# Downloads and extracts the driver source code
download_and_extract() {
    local tarball="${PKGNAME}-${PKGVER}.tar.gz"
    log_info "Downloading driver source from ${PKG_URL}..."
    # Use -f to fail on server errors, -L to follow redirects, -o to specify output file
    curl -#fL -o "${tarball}" "${PKG_URL}"

    log_info "Verifying file integrity with MD5 checksum..."
    # Use --status for silent success, which is ideal for scripting
    echo "${PKG_MD5}  ${tarball}" | md5sum -c --status || log_error "MD5 checksum verification failed. The file may be corrupt or tampered with."

    log_info "Extracting source archive..."
    tar -zxf "${tarball}"
}

# Applies necessary patches to the source for compatibility
apply_patches() {
    local source_dir="${PKGNAME}-${PKGVER}"
    log_info "Applying source code patches for Kernel $(uname -r)..."
    local audio_driver_file="${source_dir}/driver/audio_driver.c"

    # Patch 1: Replace standard <stdarg.h> with kernel-specific <linux/stdarg.h>.
    sed -i 's#include <stdarg.h>#include <linux/stdarg.h>#' "${source_dir}/driver/MTAL_LKernelAPI.c"

    # Patch 2: Fix header include paths for the DKMS build structure.
    sed -i 's#\.\./common/#common/#g' "${source_dir}/driver/"*.{h,c}
    
    # Patch 3: Replace deprecated ALSA vmalloc functions with their modern equivalents.
    sed -i 's/snd_pcm_lib_alloc_vmalloc_buffer/snd_pcm_lib_malloc_pages/g' "${audio_driver_file}"
    sed -i 's/snd_pcm_lib_free_vmalloc_buffer/snd_pcm_lib_free_pages/g' "${audio_driver_file}"

    # Patch 4: Remove the obsolete .page operator from the snd_pcm_ops struct.
    # This was removed in newer kernels, causing the build to fail.
    sed -i '/.page =/d' "${audio_driver_file}"

    log_success "Source code patched successfully."
}

# Prepares the source tree and installs the driver using DKMS
install_with_dkms() {
    local original_source_dir="${PKGNAME}-${PKGVER}"
    local dkms_source_root="/usr/src/${PKGNAME}-${PKGVER}"

    log_info "Preparing source tree for DKMS..."
    
    # Create the final destination directory for DKMS
    mkdir -p "${dkms_source_root}/common"

    # Copy the patched source files into the DKMS directory
    log_info "Copying patched source files to ${dkms_source_root}..."
    install -m 644 "${original_source_dir}/driver/"*.{c,h} "${dkms_source_root}/"
    install -m 644 "${original_source_dir}/driver/Makefile" "${dkms_source_root}/"
    install -m 644 "${original_source_dir}/common/"*.{c,h} "${dkms_source_root}/common/"

    # Download and configure the dkms.conf file
    log_info "Downloading and configuring dkms.conf..."
    curl -#fL -o "${dkms_source_root}/dkms.conf" "${DKMS_CONF_URL}"
    # Set the correct package version inside the dkms.conf file
    sed -i "s/@PKGVER@/${PKGVER}/g" "${dkms_source_root}/dkms.conf"

    log_info "Building the DKMS module..."
    dkms build -m "${PKGNAME}" -v "${PKGVER}" || log_error "DKMS build failed. Check /var/lib/dkms/${PKGNAME}/${PKGVER}/build/make.log for details."

    log_info "Installing the DKMS module..."
    dkms install -m "${PKGNAME}" -v "${PKGVER}" || log_error "DKMS install failed."

    log_success "DKMS module installed successfully."
}

# Configures the system to load the new module on boot
enable_module_autoload() {
    local mod_conf_file="/etc/modules-load.d/ravenna.conf"
    log_info "Enabling kernel module to load on boot..."
    if [[ -f "${mod_conf_file}" ]]; then
        log_warning "Module configuration file already exists at ${mod_conf_file}. Skipping."
    else
        # The module name defined in the dkms.conf is "MergingRavennaALSA"
        echo "MergingRavennaALSA" > "${mod_conf_file}"
    fi
}

# --- Main Execution ---

main() {
    # Create a temporary directory for all operations and set a trap to clean it up on exit
    WORKDIR=$(mktemp -d)
    # shellcheck disable=SC2064
    trap "rm -rf '${WORKDIR}'" EXIT
    
    cd "${WORKDIR}"

    # Initial checks and user confirmation
    check_root
    log_info "Welcome to the AES67 Ravenna ALSA DKMS Driver Installer."
    check_distro
    prompt_user "Do you want to proceed with the installation?" || { log_warning "Installation cancelled by user."; exit 0; }

    # Core installation steps
    install_dependencies
    download_and_extract
    apply_patches
    install_with_dkms
    enable_module_autoload

    # Final messages
    log_success "Installation complete!"
    log_info "You can check if the module is loaded after reboot with: lsmod | grep -i ravenna"
    
    if prompt_user "The system needs to reboot to finalize the installation. Reboot now?"; then
        log_info "Rebooting system..."
        reboot
    else
        log_warning "Please reboot your system later to load the new kernel module."
    fi
}

# Run the main function with all script arguments
main "$@"

exit 0
