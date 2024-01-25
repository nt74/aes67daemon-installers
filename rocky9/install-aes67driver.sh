#!/bin/bash
# Script: install-aes67driver.sh
# Author: nikos.toutountzoglou@svt.se
# Description: DKMS driver installation script for Rocky Linux 9

# Stop script on NZEC
set -e
# Stop script if unbound variable found (use ${var:-} if intentional)
set -u
# By default cmd1 | cmd2 returns exit code of cmd2 regardless of cmd1 success
# This is causing it to fail
set -o pipefail

# Variables
PKGDIR="$HOME/src/ravenna-alsa-lkm-dkms"
DRIVERUSRC="https://bitbucket.org/MergingTechnologies/ravenna-alsa-lkm.git"

# Enable Extra Packages for Enterprise Linux 9
echo "Welcome to AES67 Deamon DKMS driver intallation script."

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
git clone $DRIVERUSRC

# Bug fixes for latest kernel
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
