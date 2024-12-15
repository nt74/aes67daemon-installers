#!/usr/bin/env bash
# Script: install-aes67driver.sh
# Author: nikos.toutountzoglou@svt.se
# Description: AES67 Daemon DKMS driver installation script for Rocky Linux 9
# Revision: 1.4

set -euo pipefail

# Variables
PKGDIR="$HOME/src/ravenna-alsa-lkm-dkms"
PKGNAME="ravenna-alsa-lkm"
PKGVER="1.11"
RAVENNA_DKMS_PKG="https://github.com/bondagit/${PKGNAME}/archive/refs/tags/v${PKGVER}.tar.gz"
RAVENNA_DKMS_VER="1.1.93"
RAVENNA_DKMS_MD5="91ef2b6eaf4e8cd141a036c98c4dab18"

# Colors
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

# Logging Functions
function log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

function log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

function log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# Functions
function prompt_user() {
    local prompt="$1"
    while true; do
        read -r -p "$prompt (y/n) " response
        case "$response" in
            [Yy]) return 0 ;;
            [Nn]) return 1 ;;
            *) echo "Please answer 'y' or 'n'." ;;
        esac
    done
}

function check_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        [[ "${ID}" == "rocky" && "${VERSION_ID%%.*}" == "9" ]] || log_error "This script supports only Rocky Linux 9."
    else
        log_error "Unable to detect Linux distribution."
    fi
}

function install_dependencies() {
    log_info "Installing necessary packages..."
    sudo dnf install -y epel-release
    sudo /usr/bin/crb enable
    sudo dnf groupinstall -y "Development Tools"
    sudo dnf install -y dkms kernel-headers-$(uname -r)
    sudo dnf makecache
}

function download_driver() {
    log_info "Downloading driver from upstream source..."
    curl -# -o "${PKGNAME}-${PKGVER}.tar.gz" -LO "${RAVENNA_DKMS_PKG}"
    echo "${RAVENNA_DKMS_MD5}  ${PKGNAME}-${PKGVER}.tar.gz" | md5sum -c || log_error "MD5 checksum verification failed."
    tar -xf "${PKGNAME}-${PKGVER}.tar.gz"
}

function apply_patches() {
    log_info "Applying patches..."
    sed -i 's#include <stdarg.h>#include <linux/stdarg.h>#g' driver/MTAL_LKernelAPI.c
    sed -i 's/\.\./common/g' driver/*
}

function setup_dkms() {
    log_info "Setting up DKMS driver..."
    mkdir -p "build/usr/src/${PKGNAME}-${RAVENNA_DKMS_VER}/common"
    curl -# -o dkms.conf -LO https://raw.githubusercontent.com/nt74/aes67daemon-installers/main/rocky9/dkms.conf
    sed -i "s/@PKGVER@/${RAVENNA_DKMS_VER}/g" dkms.conf
    install -Dm644 dkms.conf "build/usr/src/${PKGNAME}-${RAVENNA_DKMS_VER}/dkms.conf"
    install -Dm644 driver/*.{c,h} "build/usr/src/${PKGNAME}-${RAVENNA_DKMS_VER}/"
    install -Dm644 common/*.{c,h} "build/usr/src/${PKGNAME}-${RAVENNA_DKMS_VER}/common/"
    install -Dm644 driver/Makefile "build/usr/src/${PKGNAME}-${RAVENNA_DKMS_VER}/"
}

function install_dkms() {
    log_info "Installing DKMS driver..."
    sudo cp -R "build/usr/src/${PKGNAME}-${RAVENNA_DKMS_VER}" /usr/src
    sudo dkms build -m "${PKGNAME}" -v "${RAVENNA_DKMS_VER}"
    sudo dkms install -m "${PKGNAME}" -v "${RAVENNA_DKMS_VER}"
}

function enable_autoload() {
    log_info "Enabling module autoload..."
    if [[ ! -f /etc/modules-load.d/aes67daemon.conf ]]; then
        echo "MergingRavennaALSA" | sudo tee /etc/modules-load.d/aes67daemon.conf
    fi
}

function reboot_system() {
    log_info "The system needs to reboot to complete the installation."
    if prompt_user "Would you like to reboot now?"; then
        log_info "Rebooting the system..."
        sudo reboot
    else
        log_info "Reboot skipped. Please remember to reboot later to load the driver."
    fi
}

# Main Script
check_distro
log_info "Welcome to AES67 Daemon DKMS driver installation script."
prompt_user "Proceed with installation?" || exit 0

[[ -d "$PKGDIR" ]] && {
    log_warning "Source directory '$PKGDIR' already exists."
    prompt_user "Delete and reinstall?" || exit 0
    rm -rf "$PKGDIR"
}

mkdir -p "$PKGDIR" && cd "$PKGDIR"
install_dependencies
download_driver
cd "${PKGNAME}-${PKGVER}"
apply_patches
setup_dkms
install_dkms
enable_autoload

log_info "Installation complete. To check if module is loaded type 'lsmod | grep Ravenna'."
reboot_system
exit 0
