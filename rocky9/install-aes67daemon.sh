#!/usr/bin/env bash
# Script: install-aes67daemon.sh
# Author: nikos.toutountzoglou@svt.se
# Description: AES67 Ravenna Daemon installer for Rocky Linux 9
# Revision: 1.3

# Define color codes
NC='\033[0m'       # No Color
INFO='\033[0;32m'  # Green
WARN='\033[0;33m'  # Yellow
ERROR='\033[0;31m' # Red

# Function to print info messages
info() {
	echo -e "${INFO}[INFO] $1${NC}"
}

# Function to print warning messages
warn() {
	echo -e "${WARN}[WARN] $1${NC}"
}

# Function to print error messages
error() {
	echo -e "${ERROR}[ERROR] $1${NC}"
}

# Set bash options for robust error handling
set -euo pipefail

# Variables
PKGDIR="${HOME}/src/aes67-daemon"
PKGNAME="aes67-linux-daemon"
PKGVER="2.0.2"
AES67_DAEMON_PKG="https://github.com/bondagit/${PKGNAME}/archive/refs/tags/v${PKGVER}.tar.gz"
AES67_DAEMON_PKG_MD5="5234793f638937eb6c1a99a38dbd55f2"

# Modules Driver (Ver. 1.11)
RAVENNA_DRIVER_PKGVER="1.11"
RAVENNA_DRIVER_PKG="https://github.com/bondagit/ravenna-alsa-lkm/archive/refs/tags/v${RAVENNA_DRIVER_PKGVER}.tar.gz"
RAVENNA_DRIVER_MD5="91ef2b6eaf4e8cd141a036c98c4dab18"

# Web-UI (Ver. 2.0.2)
WEBUI_PKG="https://github.com/bondagit/aes67-linux-daemon/releases/download/v${PKGVER}/webui.tar.gz"
WEBUI_PKG_MD5="a61aa1a1c839ce9cd8f7c4e845f40ae6"

# HTTP-Lib (Git-commit: 07c6e58951931f8c74de8291ff35a3298fe481c4)
HTTPLIB_PKG="https://github.com/bondagit/cpp-httplib/archive/07c6e58951931f8c74de8291ff35a3298fe481c4.zip"
HTTPLIB_PKG_MD5="79507658cac131d441f0439a4c218a2d"

# FAAC source from GitHub
FAAC_REPO="https://github.com/knik0/faac.git"
FAAC_DIR="${PKGDIR}/faac"

# Define additional directory variables
SRC_DIR="${PKGDIR}/${PKGNAME}-${PKGVER}"
THIRDPARTY_DIR="${SRC_DIR}/3rdparty"
WEBUI_DIR="${SRC_DIR}/webui"
DAEMON_DIR="${SRC_DIR}/daemon"
SYSTEMD_DIR="${SRC_DIR}/systemd"

check_distro() {
	# Check Linux distro
	if [[ -f /etc/os-release ]]; then
		# freedesktop.org and systemd
		. /etc/os-release
		OS=${ID}
		VERS_ID=${VERSION_ID}
		OS_ID="${VERS_ID:0:1}"
	elif command -v lsb_release &>/dev/null; then
		# linuxbase.org
		OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
	elif [[ -f /etc/lsb-release ]]; then
		# For some versions of Debian/Ubuntu without lsb_release command
		. /etc/lsb-release
		OS=$(echo "${DISTRIB_ID}" | tr '[:upper:]' '[:lower:]')
	elif [[ -f /etc/debian_version ]]; then
		# Older Debian/Ubuntu/etc.
		OS=debian
	else
		error "Unknown Linux distro. Exiting!"
		exit 1
	fi

	# Check if distro is Rocky Linux 9
	if [[ "${OS}" == "rocky" && "${OS_ID}" == "9" ]]; then
		info "Detected 'Rocky Linux 9'. Continuing."
	else
		error "Could not detect 'Rocky Linux 9'. Exiting."
		exit 1
	fi
}

prompt_user() {
	# Prompt user with yes/no before proceeding
	info "Welcome to AES67 Ravenna Daemon version ${PKGVER} installer script for Rocky Linux 9."
	while true; do
		read -r -p "Proceed with installation? (y/n) " yesno
		case "${yesno}" in
		[nN]) exit 0 ;;
		[yY]) break ;;
		*) warn "Please answer 'y/n'." ;;
		esac
	done
}

prepare_directory() {
	# Create a working source dir
	if [[ -d "${PKGDIR}" ]]; then
		while true; do
			warn "Source directory '${PKGDIR}' already exists."
			read -r -p "Delete it and reinstall? (y/n) " yesno
			case "${yesno}" in
			[nN]) exit 0 ;;
			[yY]) break ;;
			*) warn "Please answer 'y/n'." ;;
			esac
		done
	fi

	rm -fr "${PKGDIR}"
	mkdir -v -p "${PKGDIR}"
	cd "${PKGDIR}"
}

update_system() {
	# Update package repos cache
	info "Updating package repository cache."
	sudo dnf update -y
}

install_dependencies() {
    # Install all dependencies for building the AES67 Ravenna Daemon package
    info "Installing all dependencies for the AES67 Ravenna Daemon."

    # Enable EPEL and CRB repositories
    sudo dnf install -y epel-release
    sudo /usr/bin/crb enable

    # Install development tools
    sudo dnf groupinstall -y "Development Tools"

    # Install individual dependencies
    sudo dnf install -y \
        glibc mlocate psmisc clang cmake cpp-httplib-devel git npm \
        boost-devel valgrind alsa-lib alsa-lib-devel pulseaudio-libs-devel \
        avahi-devel autoconf automake libtool linuxptp systemd-devel \
        kernel-headers-$(uname -r)
}

build_faac_from_source() {
	# Clone and build FAAC from source
	info "Cloning and building FAAC from source."
	git clone "${FAAC_REPO}" "${FAAC_DIR}"
	cd "${FAAC_DIR}"
	./bootstrap
	./configure --prefix=/usr
	make
	sudo make install
	cd "${PKGDIR}"
}

update_ldconfig() {
	# Update ldconfig (Req. glibc, mlocate)
	info "Updating 'ldconfig' and 'updatedb'."
	sudo ldconfig
	sudo updatedb
}

download_sources() {
	# Download latest driver from upstream source
	info "Downloading latest driver from upstream source."
	curl -fSL --output "${PKGNAME}-${PKGVER}.tar.gz" "${AES67_DAEMON_PKG}" || {
		error "Failed to download AES67 Daemon package."
		exit 1
	}
	echo "${AES67_DAEMON_PKG_MD5} ${PKGNAME}-${PKGVER}.tar.gz" | md5sum -c || exit 1
	tar -xf "${PKGNAME}-${PKGVER}.tar.gz"

	# Cd to sourcedir
	cd "${SRC_DIR}"

	# Download latest 3rdparty upstream source
	cd "${THIRDPARTY_DIR}"

	# Cpp-httplib
	curl -fSL --output "cpp-httplib.zip" "${HTTPLIB_PKG}" || {
		error "Failed to download cpp-httplib."
		exit 1
	}
	echo "${HTTPLIB_PKG_MD5} cpp-httplib.zip" | md5sum -c || exit 1
	unzip -q "cpp-httplib.zip"
	mv cpp-httplib-* cpp-httplib
	# Move sourcefile to working directory
	mv "cpp-httplib.zip" "${PKGDIR}"

	# Ravenna-driver-lkm
	curl -fSL --output "ravenna-alsa-lkm-${RAVENNA_DRIVER_PKGVER}.tar.gz" "${RAVENNA_DRIVER_PKG}" || {
		error "Failed to download Ravenna driver."
		exit 1
	}
	echo "${RAVENNA_DRIVER_MD5} ravenna-alsa-lkm-${RAVENNA_DRIVER_PKGVER}.tar.gz" | md5sum -c || exit 1
	tar -xf "ravenna-alsa-lkm-${RAVENNA_DRIVER_PKGVER}.tar.gz"
	rm -f "ravenna-alsa-lkm-${RAVENNA_DRIVER_PKGVER}.tar.gz"
	cd ravenna-alsa-lkm-${RAVENNA_DRIVER_PKGVER}
	# Fix issue with newer kernels
	sed -i 's#include <stdarg.h>#include <linux/stdarg.h>#g' driver/MTAL_LKernelAPI.c
	cd driver
	make modules

	# Webui
	cd "${WEBUI_DIR}"

	curl -fSL --output "webui.tar.gz" "${WEBUI_PKG}" || {
		error "Failed to download webui."
		exit 1
	}
	echo "${WEBUI_PKG_MD5} webui.tar.gz" | md5sum -c || exit 1
	tar -xf webui.tar.gz
	npm install --cache "${PKGDIR}/npm-cache"
	npm run build
	# Move sourcefile to working directory
	mv "webui.tar.gz" "${PKGDIR}"
}

build_daemon() {
	# Daemon
	cd "${DAEMON_DIR}"

	# Build aes67-daemon
	cmake -DCPP_HTTPLIB_DIR="${THIRDPARTY_DIR}/cpp-httplib" \
		-DRAVENNA_ALSA_LKM_DIR="${THIRDPARTY_DIR}/ravenna-alsa-lkm-${RAVENNA_DRIVER_PKGVER}" \
		-DAVAHI_INCLUDE_DIR=/usr/lib64 \
		-DENABLE_TESTS=ON \
		-DWITH_AVAHI=ON \
		-DFAKE_DRIVER=OFF \
		-DWITH_SYSTEMD=ON .
	make
}

setup_systemd_service() {
	# Create systemd service and user
	while true; do
		read -r -p "Proceed with creating and enabling systemd service 'aes67-daemon.service' and user 'aes67-daemon'? (y/n) " yesno
		case "${yesno}" in
		[nN]) exit 0 ;;
		[yY]) break ;;
		*) warn "Please answer 'y/n'." ;;
		esac
	done

	cd "${SYSTEMD_DIR}"
	# Create a user for the daemon
	sudo useradd -M -l aes67-daemon -c "AES67 Linux daemon"
	# Copy the daemon binary (make sure -DWITH_SYSTEMD=ON)
	sudo cp -v "${DAEMON_DIR}/aes67-daemon" /usr/local/bin/aes67-daemon
	# Create the daemon webui and script directories
	sudo install -v -d -o aes67-daemon /var/lib/aes67-daemon /usr/local/share/aes67-daemon/scripts /usr/local/share/aes67-daemon/webui
	# Copy the ptp script
	sudo install -v -o aes67-daemon "${DAEMON_DIR}/scripts/ptp_status.sh" /usr/local/share/aes67-daemon/scripts
	# Copy the webui
	sudo cp -v -r "${WEBUI_DIR}/dist/"* /usr/local/share/aes67-daemon/webui
	# Copy daemon configuration and status files
	sudo install -v -o aes67-daemon status.json daemon.conf /etc
	# Copy the daemon systemd service definition
	sudo cp -v aes67-daemon.service /etc/systemd/system

	# Enable the daemon service
	sudo systemctl enable aes67-daemon
	sudo systemctl daemon-reexec
}

final_instructions() {
	# Before starting the daemon edit /etc/daemon.conf and make sure the interface_name parameter is set to your ethernet interface.
	info "Successfully installed AES67 Daemon. All sources are located in '${PKGDIR}'"
	info "Make sure to edit the following files:"
	info "A) /etc/daemon.conf and insert the correct interface_name parameter (i.e. eth0)"
	info "B) /etc/ptp4l.conf and insert the correct parameters (i.e. [eth0] etc)"
	info "Please reboot to activate the newly installed daemon."
}

# Main script execution
check_distro
prompt_user
prepare_directory
update_system
install_dependencies
build_faac_from_source
update_ldconfig
download_sources
build_daemon
setup_systemd_service
final_instructions

exit 0
