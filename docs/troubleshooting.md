# Troubleshooting Guide

This guide covers common issues and their solutions when setting up and running TimeCapsuleRPi.

## Table of Contents

1. [Installation Issues](#installation-issues)
2. [Connection Issues](#connection-issues)
3. [Backup Issues](#backup-issues)
4. [Performance Issues](#performance-issues)
5. [Service Issues](#service-issues)
6. [Diagnostic Commands](#diagnostic-commands)

---

## Installation Issues

### Script fails with "No USB drives detected"

**Symptom:** The install.sh script says no USB drives are connected.

**Solutions:**

1. Verify the drive is connected:
   ```bash
   lsblk
   lsusb
   ```

2. Check if the drive needs more power:
   ```bash
   # Check for under-voltage warnings
   vcgencmd get_throttled
   # Output should be 0x0. If not, you need a better power supply.
   ```

3. Try a different USB port (use USB 3.0 ports for best compatibility)

---

### Script fails at "formatting drive"

**Symptom:** The partitioning or formatting step fails.

**Solutions:**

1. Make sure the drive is not mounted:
   ```bash
   mount | grep /dev/sd
   # If mounted, unmount it:
   sudo umount /dev/sdX1
   ```

2. Check for disk errors:
   ```bash
   sudo fdisk -l /dev/sdX
   ```

3. Manually partition the drive:
   ```bash
   sudo fdisk /dev/sdX
   # o - new partition table
   # n - new partition
   # p - primary
   # 1 - partition number
   # (accept defaults)
   # w - write changes
   ```

4. Format manually:
   ```bash
   sudo mkfs.ext4 -L TimeCapsule /dev/sdX1
   ```

---

### Samba version doesn't support vfs_fruit

**Symptom:** `smbd -b | grep vfs_fruit` returns nothing.

**Solutions:**

1. Update Samba:
   ```bash
   sudo apt update
   sudo apt install --only-upgrade samba
   ```

2. Check Debian version (Bullseye or Bookworm recommended):
   ```bash
   cat /etc/os-release
   ```

3. If on old OS (Buster), upgrade to Bullseye:
   ```bash
   sudo apt update
   sudo apt full-upgrade
   ```

---

## Connection Issues

### Share doesn't appear in Finder

**Symptom:** TIMECAPSULE-PI4 doesn't show up in Finder sidebar or Network.

**Solutions:**

1. Check if Avahi is running:
   ```bash
   systemctl status avahi-daemon
   ```

2. Restart Avahi:
   ```bash
   sudo systemctl restart avahi-daemon
   ```

3. Verify mDNS service is advertised:
   ```bash
   avahi-browse -a --terminate | grep -i samba
   ```

4. Check if Avahi service file exists:
   ```bash
   ls -la /etc/avahi/services/*.service
   ```

5. Manual connection via IP:
   ```bash
   # On Mac, use Finder -> Go -> Connect to Server
   # smb://192.168.1.XX
   # Or use terminal:
   open smb://192.168.1.XX
   ```

6. Check Mac's firewall settings (System Settings -> Network -> Firewall)

---

### "Connection failed" error

**Symptom:** Cannot connect to the share even though it's visible.

**Solutions:**

1. Check if Samba is running:
   ```bash
   systemctl status smbd nmbd
   ```

2. Test locally on the Pi:
   ```bash
   smbclient -L localhost -U your_username
   ```

3. Check network connectivity:
   ```bash
   ping pi4.local
   # or
   ping 192.168.1.XX
   ```

4. Verify SMB port is open:
   ```bash
   # From Mac
   nc -zv pi4.local 445
   ```

5. Check firewall rules on Pi:
   ```bash
   sudo ufw status
   # If active, allow SMB:
   sudo ufw allow 445/tcp
   ```

6. Restart Samba:
   ```bash
   sudo systemctl restart smbd nmbd
   ```

---

### "Authentication failed" error

**Symptom:** Cannot authenticate with the Samba user.

**Solutions:**

1. Verify user exists in Samba:
   ```bash
   sudo pdbedit -L
   ```

2. Reset Samba password:
   ```bash
   sudo smbpasswd username
   ```

3. Verify user is enabled:
   ```bash
   sudo smbpasswd -e username
   ```

4. Check if user is in "valid users" list:
   ```bash
   grep "valid users" /etc/samba/smb.conf
   ```

5. Test authentication locally:
   ```bash
   smbclient //localhost/TimeCapsule -U username
   ```

---

### "You do not have permission" error

**Symptom:** Can connect but cannot write files.

**Solutions:**

1. Check mount point ownership:
   ```bash
   ls -la /mnt/timecapsule
   ```

2. Fix ownership:
   ```bash
   sudo chown -R username:username /mnt/timecapsule
   sudo chmod -R 770 /mnt/timecapsule
   ```

3. Check if drive is mounted read-only:
   ```bash
   mount | grep timecapsule
   # Look for "ro" (read-only) flag
   ```

4. Remount with write permissions:
   ```bash
   sudo mount -o remount,rw /mnt/timecapsule
   ```

5. Check disk for errors:
   ```bash
   sudo fsck -f /dev/sdX1
   # First unmount the drive!
   ```

---

## Backup Issues

### "Backup disk not available" error

**Symptom:** Time Machine says the backup disk is not available even though connected.

**Solutions:**

1. Verify the share is mounted on Mac:
   ```bash
   # In Mac terminal
   df -h | grep TimeCapsule
   ```

2. Disconnect and reconnect in Time Machine preferences:
   - System Settings -> General -> Time Machine
   - Remove the disk
   - Add it again

3. Restart Time Machine service on Mac:
   ```bash
   sudo tmutil listbackups
   ```

4. Check if sparsebundle exists on Pi:
   ```bash
   ls -la /mnt/timecapsule/
   # Should show a .sparsebundle directory
   ```

---

### Time Machine is very slow

**Symptom:** Backup is extremely slow (less than 1 MB/s).

**Solutions:**

1. Check network speed:
   ```bash
   # On Pi
   iperf3 -s

   # On Mac (install iperf3 first)
   iperf3 -c pi4.local
   ```

2. If on WiFi, switch to Ethernet:
   - WiFi adds latency and reduces throughput
   - Gigabit Ethernet is much faster for large backups

3. Check USB drive speed:
   ```bash
   sudo hdparm -Tt /dev/sdX
   # Should show 30-40 MB/s for USB 3.0 drives
   ```

4. Disable SMB encryption (if enabled):
   ```ini
   # In /etc/samba/smb.conf
   smb encrypt = off
   sudo systemctl restart smbd
   ```

5. First backup is always slow:
   - First backup: several hours (full backup)
   - Incremental backups: minutes (only changed files)

---

### Time Machine reports "not enough space"

**Symptom:** Time Machine says there's not enough space but the drive is not full.

**Solutions:**

1. Check actual disk usage:
   ```bash
   df -h /mnt/timecapsule
   ```

2. Check quota setting:
   ```bash
   grep "time machine max size" /etc/samba/smb.conf
   ```

3. Increase quota in smb.conf:
   ```ini
   fruit:time machine max size = 4T
   sudo systemctl restart smbd
   ```

4. Let Time Machine manage old backups:
   - Time Machine automatically deletes old backups when space is needed
   - This is normal behavior

---

### Sparsebundle corruption

**Symptom:** Time Machine reports sparsebundle is corrupted.

**Solutions:**

1. Check sparsebundle integrity:
   ```bash
   ls -la /mnt/timecapsule/*.sparsebundle/
   # Look for "bands" directory and "token" file
   ```

2. Try to repair from Mac:
   ```bash
   # In Mac terminal
   hdiutil attach -readonly -nomount -noverify -noautofsck /Volumes/TimeCapsule/XXX.sparsebundle
   diskutil repairDisk diskX
   hdiutil detach /dev/diskX
   ```

3. If corrupted beyond repair:
   - Delete the sparsebundle and start fresh
   - WARNING: You lose all previous backups!
   ```bash
   sudo rm -rf /mnt/timecapsule/*.sparsebundle
   ```

---

## Performance Issues

### High CPU usage on Pi

**Symptom:** Samba process uses 100% CPU during backups.

**Solutions:**

1. This is normal during active backups
   - SMB3 encryption is CPU intensive
   - Raspberry Pi 4 can handle ~80-100 MB/s with encryption

2. Reduce encryption level:
   ```ini
   # In /etc/samba/smb.conf
   server smb encrypt = off
   ```

3. Check for smbd memory leak:
   ```bash
   ps aux | grep smbd
   # If using lots of RAM, restart Samba
   sudo systemctl restart smbd
   ```

---

### Slow wake from sleep

**Symptom:** It takes a long time for the Pi to respond after being idle.

**Solutions:**

1. Disable drive spin-down:
   ```bash
   # Edit /etc/hdparm.conf
   sudo nano /etc/hdparm.conf

   # Add:
   /dev/sdX {
       apm = 255
       spindown_time = 0
   }
   ```

2. Or install hdparm and set:
   ```bash
   sudo hdparm -S 0 /dev/sdX
   ```

---

### Network drops during backup

**Symptom:** Backup fails with network error during transfer.

**Solutions:**

1. Check WiFi signal strength:
   ```bash
   # On Pi
   iwconfig wlan0
   # Look for "Link Quality"
   ```

2. Use Ethernet instead of WiFi

3. Enable WiFi power management fix:
   ```bash
   sudo iwconfig wlan0 power off
   # To make permanent, add to /etc/rc.local
   ```

4. Check router for DHCP issues:
   - Set static IP for Pi in router settings
   - Or configure static IP in Pi's dhcpcd.conf

---

## Service Issues

### Samba fails to start

**Symptom:** `systemctl start smbd` fails.

**Solutions:**

1. Check Samba configuration:
   ```bash
   testparm
   ```

2. Check Samba logs:
   ```bash
   tail -n 50 /var/log/samba/log.smbd
   ```

3. Verify no other SMB services running:
   ```bash
   ps aux | grep -E smbd|nmbd
   ```

4. Reset Samba config:
   ```bash
   sudo mv /etc/samba/smb.conf /etc/samba/smb.conf.broken
   sudo cp /etc/samba/smb.conf.backup /etc/samba/smb.conf
   sudo systemctl restart smbd
   ```

---

### Avahi fails to start

**Symptom:** `systemctl start avahi-daemon` fails.

**Solutions:**

1. Check for port conflicts:
   ```bash
   sudo netstat -tulpn | grep 5353
   ```

2. Check Avahi logs:
   ```bash
   journalctl -u avahi-daemon -n 50
   ```

3. Verify service file syntax:
   ```bash
   xmllint --noout /etc/avahi/services/*.service
   ```

4. Reinstall Avahi:
   ```bash
   sudo apt install --reinstall avahi-daemon
   ```

---

### Drive doesn't auto-mount on boot

**Symptom:** Time Capsule drive not mounted after reboot.

**Solutions:**

1. Check fstab entry:
   ```bash
   cat /etc/fstab | grep timecapsule
   ```

2. Verify UUID is correct:
   ```bash
   sudo blkid /dev/sdX1
   ```

3. Test mount manually:
   ```bash
   sudo mount -a
   ```

4. Check for filesystem errors:
   ```bash
   sudo fsck /dev/sdX1
   ```

5. Verify drive is detected on boot:
   ```bash
   lsblk
   dmesg | grep -i usb
   ```

---

## Diagnostic Commands

### Quick Health Check

Run this on the Pi for a complete status check:

```bash
#!/bin/bash

echo "=== System Information ==="
uname -a
cat /etc/os-release | grep PRETTY_NAME

echo -e "\n=== Disk Space ==="
df -h | grep -E "Filesystem|timecapsule"

echo -e "\n=== Memory ==="
free -h

echo -e "\n=== Services Status ==="
systemctl is-active smbd && echo "Samba: Running" || echo "Samba: NOT running"
systemctl is-active nmbd && echo "NetBIOS: Running" || echo "NetBIOS: NOT running"
systemctl is-active avahi-daemon && echo "Avahi: Running" || echo "Avahi: NOT running"

echo -e "\n=== Mount Status ==="
mount | grep timecapsule && echo "Drive: Mounted" || echo "Drive: NOT mounted"

echo -e "\n=== Network ==="
ip addr show | grep -E "inet |^[0-9]: " | grep -v "127.0.0.1"

echo -e "\n=== USB Devices ==="
lsusb

echo -e "\n=== Samba Version ==="
smbd --version

echo -e "\n=== vfs_fruit Support ==="
smbd -b | grep vfs_fruit

echo -e "\n=== Recent Samba Logs ==="
tail -n 5 /var/log/samba/log.smbd 2>/dev/null || echo "No logs found"

echo -e "\n=== Avahi Services ==="
avahi-browse -a --terminate 2>/dev/null | grep -E "smb|adisk" || echo "No services found"
```

### Detailed Logs

```bash
# Samba logs
tail -f /var/log/samba/log.smbd

# Avahi logs
journalctl -u avahi-daemon -f

# Kernel messages (USB/Storage)
dmesg -w | grep -E sd[a-z]|usb

# System logs
journalctl -f
```

### Network Tests

```bash
# Test SMB connection from Mac
nc -zv pi4.local 445

# Test mDNS resolution
dns-sd -Q pi4.local

# Browse all mDNS services (Mac)
dns-sd -B _smb._tcp

# Ping test
ping -c 5 pi4.local

# Measure network speed (install iperf3 first)
# On Pi:
iperf3 -s
# On Mac:
iperf3 -c pi4.local
```

---

## Getting Help

If none of these solutions work:

1. Collect diagnostic information:
   ```bash
   # Run the health check script above and save output
   ./healthcheck.sh > diagnostics.txt
   ```

2. Check relevant log files

3. Search GitHub issues for similar problems

4. Open a new issue with:
   - Raspberry Pi model and OS version
   - macOS version
   - Exact error message
   - Diagnostic output
   - Relevant log snippets

---

**Last Updated:** 2026-02-01
