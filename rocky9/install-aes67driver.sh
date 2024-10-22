#!/usr/bin/env bash
# Script: install-aes67driver.sh
# Author: nikos.toutountzoglou@svt.se
# Description: AES67 Daemon DKMS driver installation script for Rocky Linux 9
# Revision: 1.3

# Stop script on NZEC
set -e
# Stop script if unbound variable found (use ${var:-} if intentional)
set -u
# By default cmd1 | cmd2 returns exit code of cmd2 regardless of cmd1 success
# This is causing it to fail
set -o pipefail

# Variables
PKGDIR="$HOME/src/ravenna-alsa-lkm-dkms"
PKGNAME="ravenna-alsa-lkm"
PKGVER="1.11"
RAVENNA_DKMS_PKG="https://github.com/bondagit/${PKGNAME}/archive/refs/tags/v${PKGVER}.tar.gz"
RAVENNA_DKMS_VER="1.1.93"
RAVENNA_DKMS_MD5="91ef2b6eaf4e8cd141a036c98c4dab18"

# Check Linux distro
if [ -f /etc/os-release ]; then
	# freedesktop.org and systemd
	. /etc/os-release
	OS=${ID}
	VERS_ID=${VERSION_ID}
	OS_ID="${VERS_ID:0:1}"
elif type lsb_release &>/dev/null; then
	# linuxbase.org
	OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
elif [ -f /etc/lsb-release ]; then
	# For some versions of Debian/Ubuntu without lsb_release command
	. /etc/lsb-release
	OS=$(echo ${DISTRIB_ID} | tr '[:upper:]' '[:lower:]')
elif [ -f /etc/debian_version ]; then
	# Older Debian/Ubuntu/etc.
	OS=debian
else
	# Unknown
	echo "Unknown Linux distro. Exiting!"
	exit 1
fi

# Check if distro is Rocky Linux 9
if [ $OS = "rocky" ] && [ $OS_ID = "9" ]; then
	echo "Detected 'Rocky Linux 9'. Continuing."
else
	echo "Could not detect 'Rocky Linux 9'. Exiting."
	exit 1
fi

# Prompt user with yes/no before proceeding
echo "Welcome to AES67 Daemon DKMS driver intallation script."
while true; do
	read -r -p "Proceed with installation? (y/n) " yesno
	case "$yesno" in
	n | N) exit 0 ;;
	y | Y) break ;;
	*) echo "Please answer 'y/n'." ;;
	esac
done

# Create a working source dir
if [ -d "${PKGDIR}" ]; then
	while true; do
		echo "Source directory '${PKGDIR}' already exists."
		read -r -p "Delete it and reinstall? (y/n) " yesno
		case "$yesno" in
		n | N) exit 0 ;;
		y | Y) break ;;
		*) echo "Please answer 'y/n'." ;;
		esac
	done
fi

rm -fr ${PKGDIR}
mkdir -v -p ${PKGDIR}
cd ${PKGDIR}

# Enable Extra Packages for Enterprise Linux 9
echo "Enabling Extra Packages for Enterprise Linux 9 and Development Tools."
sudo dnf install -y epel-release
sudo /usr/bin/crb enable

# Enable Development Tools
sudo dnf groupinstall -y "Development Tools"

# Update package repos cache
sudo dnf makecache

# Install Rocky Linux 9 dkms package
sudo dnf install -y dkms kernel-headers-$(uname -r)

# Download latest driver from upstream source
echo "Downloading latest driver from upstream source."
curl -# -o ${PKGNAME}-${PKGVER}.tar.gz -LO ${RAVENNA_DKMS_PKG}
echo ${RAVENNA_DKMS_MD5} ${PKGNAME}-${PKGVER}.tar.gz | md5sum -c || exit 1
tar -xf ${PKGNAME}-${PKGVER}.tar.gz

# Patches and fixes
cd ${PKGNAME}-${PKGVER}
sed -i 's#include <stdarg.h>#include <linux/stdarg.h>#g' driver/MTAL_LKernelAPI.c
sed -i 's/\.\.\/common/common/g' driver/*

# Create DKMS driver build dir
mkdir -p build/usr/src/${PKGNAME}-${RAVENNA_DKMS_VER}/common

# Download custom dkms.conf file and set correct version
curl -# -o dkms.conf -LO https://raw.githubusercontent.com/nt74/aes67daemon-installers/main/rocky9/dkms.conf
sed -i 's/@PKGVER@/1\.1\.93/g' dkms.conf

# Copy DKMS driver to correct build dirs
install -Dm644 dkms.conf build/usr/src/${PKGNAME}-${RAVENNA_DKMS_VER}/dkms.conf
cp -r driver/* build/usr/src/${PKGNAME}-${RAVENNA_DKMS_VER}
cp -r common/* build/usr/src/${PKGNAME}-${RAVENNA_DKMS_VER}/common

# Copy final DKMS driver to kernel source dir
cd build/usr/src
sudo cp -R ${PKGNAME}-${RAVENNA_DKMS_VER} /usr/src

# Build and install DKMS driver
echo "Building DKMS driver."
sudo dkms build -m ${PKGNAME} -v ${RAVENNA_DKMS_VER}
echo "Installing DKMS driver."
sudo dkms install -m ${PKGNAME} -v ${RAVENNA_DKMS_VER}

# Create autoload of module 'MergingRavennaALSA'
if [ ! -f /etc/modules-load.d/aes67daemon.conf ]; then
	echo "MergingRavennaALSA" | sudo tee -a /etc/modules-load.d/aes67daemon.conf
fi

# Prompt about final steps
echo "Successfully installed DKMS drivers, now reboot and check"
echo "if the module is loaded by typing 'lsmod | grep Ravenna'."

exit 0
