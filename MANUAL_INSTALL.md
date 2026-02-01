# TimeCapsule-Pi - Manual Installation Guide

This guide provides step-by-step instructions for manually setting up your Raspberry Pi as a Time Machine server. If you prefer an automated installation, use the `install.sh` script instead.

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Step 1: System Preparation](#step-1-system-preparation)
3. [Step 2: Install Samba](#step-2-install-samba)
4. [Step 3: Disk Setup](#step-3-disk-setup)
5. [Step 4: Configure Samba](#step-4-configure-samba)
6. [Step 5: Configure Avahi](#step-5-configure-avahi)
7. [Step 6: Create Time Machine User](#step-6-create-time-machine-user)
8. [Step 7: Testing](#step-7-testing)
9. [Step 8: Configure macOS](#step-8-configure-macos)

---

## Prerequisites

Before starting, ensure you have:

- **Raspberry Pi 4** (4GB+ RAM recommended) with Raspberry Pi OS (Bullseye or Bookworm)
- **External USB drive** (1TB+ recommended)
- **SSH access** to your Raspberry Pi
- **macOS computer** (10.9+)
- **Internet connection** on both devices

### Verify Your System

```bash
# Check Raspberry Pi OS version
cat /etc/os-release

# Check available memory
free -h

# Check available disk space
df -h
```

---

## Step 1: System Preparation

Update your system packages:

```bash
sudo apt update
sudo apt upgrade -y
sudo apt autoremove -y
```

---

## Step 2: Install Samba

Install Samba and required dependencies:

```bash
sudo apt install -y samba samba-common-bin avahi-daemon
```

Verify Samba version (must be 4.x with vfs_fruit support):

```bash
smbd --version
# Should show: Version 4.x.x
```

Check if vfs_fruit module is available:

```bash
smbd -b | grep vfs_fruit
# Should show: VFS_MODULE_FRUIT
```

---

## Step 3: Disk Setup

### 3.1 Identify Your External Drive

Connect your external USB drive to the Raspberry Pi and identify it:

```bash
# List all block devices
lsblk

# List USB devices
lsusb

# Check drive details (replace sda with your device)
sudo fdisk -l /dev/sda
```

Look for your external drive (typically `/dev/sda`, `/dev/sdb`, etc.). Note the size and make sure it's the correct drive!

### 3.2 Partition the Drive

**WARNING: This will erase all data on the drive! Make sure you have the correct device.**

```bash
# Start fdisk on your drive
sudo fdisk /dev/sda

# In fdisk, enter these commands:
# o - create new partition table
# n - create new partition (accept defaults: primary, partition 1, full disk)
# t - set partition type (choose 83 - Linux)
# w - write changes and exit
```

### 3.3 Format the Drive as ext4

```bash
sudo mkfs.ext4 -L TimeCapsule /dev/sda1
```

### 3.4 Create Mount Point

```bash
sudo mkdir -p /mnt/timecapsule
```

### 3.5 Configure Auto-Mount (fstab)

First, get the UUID of your partition:

```bash
sudo blkid /dev/sda1
# Note the UUID value, e.g.: UUID="12345678-1234-1234-1234-123456789abc"
```

Edit fstab:

```bash
sudo nano /etc/fstab
```

Add this line (replace UUID with your actual UUID):

```
UUID=your-uuid-here  /mnt/timecapsule  ext4  defaults,noatime  0  2
```

Save and exit (Ctrl+X, Y, Enter).

### 3.6 Mount the Drive

```bash
sudo mount -a
```

Verify it's mounted:

```bash
df -h | grep timecapsule
```

### 3.7 Set Permissions

```bash
# Give ownership to your user
sudo chown -R your_username:your_username /mnt/timecapsule
sudo chmod -R 770 /mnt/timecapsule
```

---

## Step 4: Configure Samba

### 4.1 Backup Original Configuration

```bash
sudo cp /etc/samba/smb.conf /etc/samba/smb.conf.backup
```

### 4.2 Copy the Template

Use the provided `setup/smb.conf` template from this repository:

```bash
# If you cloned the repo:
sudo cp setup/smb.conf /etc/samba/smb.conf

# Or manually create it (see Configuration Reference below)
```

### 4.3 Customize Configuration

Edit the Samba configuration:

```bash
sudo nano /etc/samba/smb.conf
```

**Important changes to make:**

1. Update `valid users` with your actual username:
   ```ini
   valid users = your_username
   ```

2. Optionally change the share name, server name, or quota:
   ```ini
   [TimeCapsule]
       path = /mnt/timecapsule
       fruit:time machine max size = 2T    # Adjust as needed
   ```

### 4.4 Validate Configuration

```bash
testparm
```

Should show "Loaded services file OK" without errors.

### 4.5 Restart Samba

```bash
sudo systemctl restart smbd nmbd
sudo systemctl enable smbd nmbd
```

### 4.6 Verify Samba is Running

```bash
sudo systemctl status smbd nmbd
```

---

## Step 5: Configure Avahi

Avahi allows macOS to automatically discover your Time Capsule.

### 5.1 Copy the Service File

Use the provided `setup/timecapsule.service` from this repository:

```bash
# If you cloned the repo:
sudo cp setup/timecapsule.service /etc/avahi/services/timecapsule.service

# Or create it manually (see Configuration Reference below)
```

### 5.2 Restart Avahi

```bash
sudo systemctl restart avahi-daemon
sudo systemctl enable avahi-daemon
```

### 5.3 Verify Avahi is Running

```bash
sudo systemctl status avahi-daemon
```

---

## Step 6: Create Time Machine User

You need a Samba user for Time Machine authentication.

### 6.1 Create System User (if not exists)

```bash
# Create user without home directory
sudo adduser --no-create-home --gecos "" timemachine
# Or use your existing user
```

### 6.2 Create Samba Password

```bash
sudo smbpasswd -a your_username
# Enter and confirm a password
```

### 6.3 Enable User for Samba

```bash
sudo smbpasswd -e your_username
```

---

## Step 7: Testing

### 7.1 Test Samba Share Locally

```bash
smbclient -L localhost -U your_username
```

You should see the `TimeCapsule` share listed.

### 7.2 Test Mounting the Share

```bash
# Create a test mount point
mkdir ~/tm_test

# Mount the share
sudo mount -t cifs //localhost/timecapsule ~/tm_test \
  -o username=your_username,password=your_password,vers=3.0

# List contents
ls ~/tm_test

# Unmount when done
sudo umount ~/tm_test
rmdir ~/tm_test
```

### 7.3 Check Network Visibility

On your Mac, open Finder and look for "TIMECAPSULE-PI4" under:
- **Shared** section in sidebar
- **Network** section

---

## Step 8: Configure macOS

### 8.1 Add Time Machine Backup Disk

1. Open **System Settings** → **General** → **Time Machine**
2. Click **Add Backup Disk** or the **+** button
3. Select **TIMECAPSULE-PI4** → **TimeCapsule**
4. Click **Set Up Disk**
5. Enter your Samba username and password
6. Check **Remember this password in my keychain**
7. Click **Connect**

### 8.2 First Backup

- The first backup will take several hours (depends on data size)
- Keep your Mac connected to the same network as the Pi
- You can monitor progress in Time Machine settings

### 8.3 Verify Backup

After completion, verify:

```bash
# On Raspberry Pi, check backup files
ls -la /mnt/timecapsule/
```

You should see a `.Spotlight-V100` folder and a `Backups.backupdb` folder.

---

## Configuration Reference

### Complete smb.conf

```ini
[global]
    # Server identification
    server string = Raspberry Pi 4 Time Machine
    workgroup = WORKGROUP
    netbios name = TIMECAPSULE-PI4

    # Logging
    log file = /var/log/samba/log.%m
    max log size = 1000
    log level = 2
    pid directory = /var/run/samba
    lock directory = /var/run/samba

    # SMB Protocol (force SMB2/3, no SMB1)
    min protocol = SMB2
    max protocol = SMB3
    server min protocol = SMB2

    # Time Machine specific options - vfs_fruit
    fruit:time machine = yes
    fruit:delete vacuum files = yes
    fruit:veto apple double = no
    fruit:metadata = stream
    fruit:encoding = native
    fruit:copyfile = yes
    fruit:model = TimeCapsule

    # VFS modules for macOS compatibility
    vfs objects = catia fruit streams_xattr

    # Authentication
    security = user
    passdb backend = tdbsam
    encrypt passwords = yes

    # Performance tuning
    read raw = yes
    write raw = yes
    aio read size = 16384
    aio write size = 16384

    # Network
    bind interfaces only = yes
    interfaces = 127.0.0.1 192.168.1.0/24

# Time Machine Share
[TimeCapsule]
    comment = Time Machine Backup on Pi4
    path = /mnt/timecapsule
    browseable = yes
    read only = no
    create mask = 0666
    directory mask = 0777
    guest ok = no
    valid users = your_username

    # Time Machine specific
    fruit:time machine max size = 2T
    vfs objects = catia fruit streams_xattr
```

### Complete Avahi Service File

Save as `/etc/avahi/services/timecapsule.service`:

```xml
<?xml version="1.0" standalone='no'?><!--*-nxml-*-->
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">%h</name>
  <service>
    <type>_smb._tcp</type>
    <port>445</port>
  </service>
  <service>
    <type>_device-info._tcp</type>
    <port>0</port>
    <txt-record>model=TimeCapsule</txt-record>
  </service>
  <service>
    <type>_adisk._tcp</type>
    <port>9</port>
    <txt-record>dk0=adVN=TimeCapsule,adVF=0x82</txt-record>
    <txt-record>sys=waMA=xx:xx:xx:xx:xx:xx</txt-record>
  </service>
</service-group>
```

**Note:** Replace `xx:xx:xx:xx:xx:xx` with your Pi's Ethernet MAC address (get it with `ip link show`).

---

## Troubleshooting

For common issues and solutions, see [docs/troubleshooting.md](docs/troubleshooting.md).

### Quick Checks

```bash
# Check Samba version and modules
smbd --version
smbd -b | grep vfs_fruit

# Check services status
systemctl status smbd nmbd avahi-daemon

# Check disk mount
df -h | grep timecapsule

# Test Samba config
testparm

# List Samba shares
smbclient -L localhost -U your_username

# Check Avahi services
avahi-browse -a --terminate
```

---

## Next Steps

- [ ] Configure Tailscale for remote access
- [ ] Set up multiple users
- [ ] Adjust quota limits
- [ ] Monitor backup logs

For advanced configuration, see [docs/architecture.md](docs/architecture.md).
