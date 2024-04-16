#!/bin/bash
# Script: install-aes67driver.sh
# Author: nikos.toutountzoglou@svt.se
# Description: DKMS driver installation script for Rocky Linux 9
# Revision: 1.0

# Stop script on NZEC
set -e
# Stop script if unbound variable found (use ${var:-} if intentional)
set -u
# By default cmd1 | cmd2 returns exit code of cmd2 regardless of cmd1 success
# This is causing it to fail
set -o pipefail

# Variables
PKGDIR="$HOME/src/ravenna-alsa-lkm-dkms"
DRIVERUSRC="https://github.com/bondagit/ravenna-alsa-lkm.git"

# Check Linux distro
if [ -f /etc/os-release ]; then
	# freedesktop.org and systemd
	. /etc/os-release
	OS=${ID}
	VERS_ID=${VERSION_ID}
	OS_ID="${VERS_ID:0:1}"
elif type lsb_release &> /dev/null; then
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
while true
do
	read -r -p "Proceed with installation? (y/n) " yesno
	case "$yesno" in
		n|N) exit 0;;
		y|Y) break;;
		*) echo "Please answer 'y/n'.";;
	esac
done

# Enable Extra Packages for Enterprise Linux 9
echo "Enabling Extra Packages for Enterprise Linux 9 and Development Tools."
sudo dnf install epel-release
sudo /usr/bin/crb enable

# Enable Development Tools
sudo dnf groupinstall "Development Tools"

# Update package repos cache
sudo dnf makecache

# Install Rocky Linux 9 dkms package
sudo dnf install dkms kernel-headers-$(uname -r)

# Create a working source dir
mkdir -p $PKGDIR
cd $PKGDIR

# Download latest driver from upstream source
echo "Downloading latest driver from upstream source."
git clone --single-branch --branch aes67-daemon $DRIVERUSRC

# Fixes for latest kernel
cd ravenna-alsa-lkm
sed -i 's#include <stdarg.h>#include <linux/stdarg.h>#g' driver/MTAL_LKernelAPI.c
sed -i 's/\.\.\/common/common/g' driver/*

# Create DKMS driver build dir
mkdir -p build/usr/src/ravenna-alsa-lkm-1.1.93/common

# Download dkms.conf file from AUR source and set correct version
curl -o dkms.conf -LO https://raw.githubusercontent.com/nt74/aes67daemon-installers/main/rocky9/dkms.conf
sed -i 's/@PKGVER@/1\.1\.93/g' dkms.conf

# Copy DKMS driver to correct build dirs
install -Dm644 dkms.conf build/usr/src/ravenna-alsa-lkm-1.1.93/dkms.conf
cp -r driver/* build/usr/src/ravenna-alsa-lkm-1.1.93
cp -r common/* build/usr/src/ravenna-alsa-lkm-1.1.93/common

# Copy final DKMS driver to kernel source dir
cd build/usr/src
sudo cp -R ravenna-alsa-lkm-1.1.93 /usr/src

# Build and install DKMS driver
echo "Building DKMS driver."
sudo dkms build -m ravenna-alsa-lkm -v 1.1.93
echo "Installing DKMS driver."
sudo dkms install -m ravenna-alsa-lkm -v 1.1.93

# Create autoload of module
echo "MergingRavennaALSA" | sudo tee -a /etc/modules-load.d/aes67daemon.conf

# Prompt about final steps
echo "Successfully installed DKMS drivers, now reboot and check"
echo "if the module is loaded by typing 'lsmod | grep Ravenna'."

exit 0
