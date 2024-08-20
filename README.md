# AES67 Linux Daemon installer help scripts
Custom Linux shell scripts for installing aes67-daemon and drivers.

AES67 Linux Daemon is a Linux implementation of AES67 interoperability standard used to distribute and synchronize real time audio over Ethernet. 

For more info check:

https://github.com/bondagit/aes67-linux-daemon

https://bitbucket.org/MergingTechnologies/ravenna-alsa-lkm/src/master/README.md 

## Instructions
```
mkdir -p ~/src && cd ~/src
```
```
git clone https://github.com/nt74/aes67daemon-installers.git
```
```
cd aes67daemon-installers/rocky9
```
```
chmod +x install-*
```

It is now possible to run any installer script by running:

./install-aes67driver.sh

and

./install-aes67daemon.sh

Module signing
--

By default, DKMS generates a self signed certificate for signing modules at
build time and signs every module that it builds before it gets compressed in
the configured kernel compression mechanism of choice.

This requires the `openssl` command to be present on the system.

Private key and certificate are auto generated the first time DKMS is run and
placed in `/var/lib/dkms`. These certificate files can be pre-populated with
your own certificates of choice.

The location as well can be changed by setting the appropriate variables in
`/etc/dkms/framework.conf`. For example, to allow usage of the system default
Ubuntu `update-secureboot-policy` set the configuration file as follows:
```
mok_signing_key="/var/lib/shim-signed/mok/MOK.priv"
mok_certificate="/var/lib/shim-signed/mok/MOK.der"
```
NOTE: If any of the files specified by `mok_signing_key` and
`mok_certificate` are non-existant, dkms will re-create both files.

The paths specified in `mok_signing_key`, `mok_certificate` and `sign_file` can
use the variable `${kernelver}` to represent the target kernel version.
```
sign_file="/lib/modules/${kernelver}/build/scripts/sign-file"
```

The variable `mok_signing_key` can also be a `pkcs11:...` string for a [PKCS#11
engine](https://www.rfc-editor.org/rfc/rfc7512), as long as the `sign_file`
program supports it.

Secure Boot
--

On an UEFI system with Secure Boot enabled, modules require signing (as
described in the above paragraph) before they can be loaded and the firmware of
the system must know the correct public certificate to verify the module
signature.

For importing the MOK certificate make sure `mokutil` is installed.

To check if Secure Boot is enabled:

```
# mokutil --sb-state
SecureBoot enabled
```

With the appropriate key material on the system, enroll the public key:

```
# mokutil --import /var/lib/dkms/mok.pub
```

You'll be prompted to create a password. Enter it twice.

Reboot the computer. At boot you'll see the MOK Manager EFI interface:

![SHIM UEFI key management](/images/mok-key-1.png)

Press any key to enter it, then select "Enroll MOK":

![Perform MOK management](/images/mok-key-2.png)

Then select "Continue":

![Enroll MOK](/images/mok-key-3.png)

And confirm with "Yes" when prompted:

![Enroll the key(s)?](/images/mok-key-4.png)

After this, enter the password you set up with `mokutil --import` in the
previous step:

![Enroll the key(s)?](/images/mok-key-5.png)

At this point you are done, select "OK" and the computer will reboot trusting
the key for your modules:

![Perform MOK management](/images/mok-key-6.png)

After reboot, you can inspect the MOK certificates with the following command:

```
# mokutil --list-enrolled | grep DKMS
        Subject: CN=DKMS module signing key
```

To check the signature on a built DKMS module that is installed on a system:

```
# modinfo MergingRavennaALSA | grep ^signer
signer:         DKMS module signing key
```

The module can now be loaded without issues.

Further Documentation
--

Once DKMS is installed, you can reference its man page for further information
on different DKMS options and also to understand the formatting of a module's
dkms.conf configuration file.

The DKMS project is located at: https://github.com/dell/dkms
