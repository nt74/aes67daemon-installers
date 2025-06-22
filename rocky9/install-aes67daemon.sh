#!/usr/bin/env bash
# Script: install-aes67daemon.sh
# Author: nikos.toutountzoglou@svt.se
# Description: AES67 Ravenna Daemon installer for Rocky Linux 9 (release 9.6). Creates a persistent build directory for offline use.
# Revision: 1.5

set -euo pipefail

# --- Configuration ---
# AES67 Daemon
DAEMON_PKGNAME="aes67-linux-daemon"
DAEMON_PKGVER="2.1.0"
DAEMON_URL="https://github.com/bondagit/${DAEMON_PKGNAME}/archive/refs/tags/v${DAEMON_PKGVER}.tar.gz"
DAEMON_MD5="ecd0556f6ef700e1c2288108ac431268"

# Ravenna ALSA Driver Source (Dependency)
RAVENNA_DRIVER_PKGNAME="ravenna-alsa-lkm"
RAVENNA_DRIVER_PKGVER="1.15"
RAVENNA_DRIVER_URL="https://github.com/bondagit/${RAVENNA_DRIVER_PKGNAME}/archive/refs/tags/v${RAVENNA_DRIVER_PKGVER}.tar.gz"
RAVENNA_DRIVER_MD5="149a9df6c7f5d6a5c01bf5e1b50a26f3"

# WebUI for the Daemon
# Note: The WebUI release is still tied to the v2.0.2 daemon release tag.
WEBUI_URL="https://github.com/bondagit/aes67-linux-daemon/releases/download/v2.0.2/webui.tar.gz"
WEBUI_MD5="a61aa1a1c839ce9cd8f7c4e845f40ae6"

# C++ HTTP Library (Dependency)
HTTPLIB_URL="https://github.com/bondagit/cpp-httplib/archive/07c6e58951931f8c74de8291ff35a3298fe481c4.zip"
HTTPLIB_MD5="79507658cac131d441f0439a4c218a2d"

# FAAC Codec (Dependency)
FAAC_REPO_URL="https://github.com/knik0/faac.git"

# --- Global Variables ---
WORKDIR=""

# --- Style and Logging ---
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO] $1${NC}"; }
log_success() { echo -e "${GREEN}[SUCCESS] $1${NC}"; }
log_warning() { echo -e "${YELLOW}[WARNING] $1${NC}"; }
log_error() { echo -e "${RED}[ERROR] $1${NC}" >&2; exit 1; }

# --- Helper Functions ---

check_distro() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        [[ "${ID}" == "rocky" && "${VERSION_ID%%.*}" == "9" ]] || log_error "This script is intended only for Rocky Linux 9."
        log_info "Rocky Linux 9 distribution confirmed."
    else
        log_error "Unable to detect the Linux distribution."
    fi
}

prompt_user() {
    local prompt_message="$1"
    while true; do
        read -r -p "$prompt_message (y/n) " response
        case "$response" in
            [Yy]*) return 0;;
            [Nn]*) return 1;;
            *) echo "Please answer 'y' or 'n'." ;;
        esac
    done
}

# --- Installation Functions ---

install_dependencies() {
    log_info "Installing build dependencies using sudo..."
    sudo dnf install -y epel-release
    sudo crb enable
    sudo dnf groupinstall -y "Development Tools"
    
    # Install other dependencies
    sudo dnf install -y \
        glibc mlocate psmisc clang cmake cpp-httplib-devel git \
        boost-devel valgrind alsa-lib alsa-lib-devel pulseaudio-libs-devel \
        avahi-devel autoconf automake libtool linuxptp systemd-devel

    # The WebUI build process requires a modern version of Node.js.
    # The default Node.js in Rocky 9 is too old.
    log_info "Setting up repository for a modern version of Node.js..."
    # This command downloads and executes the NodeSource setup script for Node.js 20.x (LTS)
    curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
    
    log_info "Removing conflicting system npm package..."
    # Explicitly remove the old npm package to prevent file conflicts.
    # The new nodejs package from NodeSource includes its own npm.
    sudo dnf remove -y npm

    log_info "Installing Node.js (and removing conflicting old versions)..."
    # Use --allowerasing to resolve conflicts with the system's default nodejs v16 package.
    sudo dnf install -y --allowerasing nodejs

    log_success "Dependencies installed."
}

build_and_install_faac() {
    log_info "Cloning and building FAAC audio codec from source..."
    git clone "${FAAC_REPO_URL}" "faac"
    cd "faac"
    ./bootstrap
    ./configure --prefix=/usr
    make
    sudo make install
    cd ..
    log_success "FAAC installed."
    
    log_info "Updating dynamic linker cache..."
    sudo ldconfig
}

download_and_extract() {
    log_info "Downloading all required source packages..."
    fetch() {
        local url="$1"
        local filename="$2"
        local md5="$3"
        log_info "Downloading ${filename}..."
        curl -#fL -o "${filename}" "${url}"
        echo "${md5}  ${filename}" | md5sum -c --status || log_error "MD5 checksum failed for ${filename}."
    }

    fetch "${DAEMON_URL}" "${DAEMON_PKGNAME}-${DAEMON_PKGVER}.tar.gz" "${DAEMON_MD5}"
    fetch "${RAVENNA_DRIVER_URL}" "${RAVENNA_DRIVER_PKGNAME}-${RAVENNA_DRIVER_PKGVER}.tar.gz" "${RAVENNA_DRIVER_MD5}"
    fetch "${WEBUI_URL}" "webui.tar.gz" "${WEBUI_MD5}"
    fetch "${HTTPLIB_URL}" "cpp-httplib.zip" "${HTTPLIB_MD5}"

    log_info "Extracting archives..."
    tar -zxf "${DAEMON_PKGNAME}-${DAEMON_PKGVER}.tar.gz"
}

prepare_source_tree() {
    local daemon_src_dir="${DAEMON_PKGNAME}-${DAEMON_PKGVER}"
    local thirdparty_dir="${daemon_src_dir}/3rdparty"
    
    log_info "Arranging source tree for the daemon build..."
    tar -zxf "${RAVENNA_DRIVER_PKGNAME}-${RAVENNA_DRIVER_PKGVER}.tar.gz" -C "${thirdparty_dir}"
    unzip -q "cpp-httplib.zip" -d "${thirdparty_dir}"
    mv "${thirdparty_dir}/cpp-httplib-"* "${thirdparty_dir}/cpp-httplib"
    tar -zxf "webui.tar.gz" -C "${daemon_src_dir}/webui"
    log_success "Source tree prepared."
}

build_webui() {
    local webui_dir="${DAEMON_PKGNAME}-${DAEMON_PKGVER}/webui"
    log_info "Building the WebUI component (this may take a while)..."
    cd "${webui_dir}"
    npm install --cache "${WORKDIR}/npm-cache"
    npm run build
    cd "${WORKDIR}"
    log_success "WebUI built successfully."
}

build_daemon() {
    local daemon_build_dir="${DAEMON_PKGNAME}-${DAEMON_PKGVER}/daemon"
    local thirdparty_dir_abs="${WORKDIR}/${DAEMON_PKGNAME}-${DAEMON_PKGVER}/3rdparty"

    log_info "Building the AES67 daemon..."
    cd "${daemon_build_dir}"

    cmake -DCPP_HTTPLIB_DIR="${thirdparty_dir_abs}/cpp-httplib" \
          -DRAVENNA_ALSA_LKM_DIR="${thirdparty_dir_abs}/${RAVENNA_DRIVER_PKGNAME}-${RAVENNA_DRIVER_PKGVER}" \
          -DENABLE_TESTS=OFF -DWITH_AVAHI=ON -DFAKE_DRIVER=OFF -DWITH_SYSTEMD=ON .
    make
    cd "${WORKDIR}"
    log_success "AES67 daemon built successfully."
}

install_daemon_service() {
    local src_dir="${DAEMON_PKGNAME}-${DAEMON_PKGVER}"

    if prompt_user "Proceed with installing and enabling the 'aes67-daemon' service?"; then
        log_info "Installing daemon and systemd service using sudo..."
        
        # Check if user exists before trying to create it
        if ! id -u "aes67-daemon" &>/dev/null; then
            log_info "Creating system user 'aes67-daemon'..."
            sudo useradd -M -r -s /sbin/nologin aes67-daemon -c "AES67 Linux daemon"
        else
            log_warning "User 'aes67-daemon' already exists, skipping creation."
        fi

        sudo install -m 755 "${src_dir}/daemon/aes67-daemon" "/usr/local/bin/aes67-daemon"
        sudo install -d -o aes67-daemon /var/lib/aes67-daemon
        sudo install -d /usr/local/share/aes67-daemon/scripts
        sudo install -d /usr/local/share/aes67-daemon/webui
        sudo install -m 755 "${src_dir}/daemon/scripts/ptp_status.sh" /usr/local/share/aes67-daemon/scripts/
        sudo cp -r "${src_dir}/webui/dist/"* /usr/local/share/aes67-daemon/webui/
        sudo install -m 644 -o aes67-daemon "${src_dir}/systemd/status.json" /etc/
        sudo install -m 644 "${src_dir}/systemd/daemon.conf" /etc/
        sudo install -m 644 "${src_dir}/systemd/aes67-daemon.service" /etc/systemd/system/
        sudo systemctl daemon-reload
        sudo systemctl enable aes67-daemon.service
        log_success "Daemon service installed and enabled."
    else
        log_warning "Service installation skipped."
    fi
}

final_instructions() {
    log_success "AES67 Daemon installation process finished."
    log_warning "ACTION REQUIRED: Before starting the daemon, you must configure it."
    log_info "1. Edit '/etc/daemon.conf' and set the 'interface_name' to your network interface (e.g., eth0)."
    log_info "2. Edit '/etc/ptp4l.conf' to match your PTP network configuration."
    log_info "Once configured, you can start the service with: sudo systemctl start aes67-daemon.service"

    echo
    log_success "All source and build files have been saved in '${WORKDIR}'."
    log_info "You can copy this entire directory to an offline machine for installation."

    if prompt_user "Do you want to remove the build directory '${WORKDIR}' now?"; then
        log_info "Removing build directory..."
        rm -rf "${WORKDIR}"
        log_success "Cleanup complete."
    else
        log_warning "Build directory has been kept."
    fi
}

# --- Main Execution ---

main() {
    log_info "AES67 Ravenna Daemon v${DAEMON_PKGVER} Installer for Rocky Linux 9 (9.6, Kernel 5.14)"
    log_info "This script must be run as a normal user."
    log_info "It will ask for your password when 'sudo' is needed for system-wide changes."
    
    if ! command -v sudo &> /dev/null; then
        log_error "'sudo' command not found. Please install it."
    fi

    if [[ "$EUID" -eq 0 ]]; then
       log_error "This script should NOT be run as root. Run it as a normal user with sudo privileges."
    fi

    # "Prime" the sudo password prompt.
    log_info "Please enter your password now if prompted, to grant sudo permissions for the script."
    sudo -v
    if [[ $? -ne 0 ]]; then
      log_error "Could not acquire sudo privileges."
    fi

    WORKDIR="${HOME}/aes67-daemon-build"

    check_distro
    log_info "Build files will be stored in: ${WORKDIR}"

    if [[ -d "${WORKDIR}" ]]; then
        log_warning "The directory '${WORKDIR}' already exists."
        if ! prompt_user "Do you want to delete it and reinstall?"; then
            log_warning "Installation cancelled by user."
            exit 0
        fi
        log_info "Removing existing build directory."
        rm -rf "${WORKDIR}"
    fi

    mkdir -p "${WORKDIR}"
    cd "${WORKDIR}"
    
    # Core installation steps
    install_dependencies
    build_and_install_faac
    download_and_extract
    prepare_source_tree
    build_webui
    build_daemon
    install_daemon_service
    final_instructions
}

main "$@"

exit 0
