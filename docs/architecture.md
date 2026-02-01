# Architecture Documentation

This document provides a deep dive into the technical architecture of TimeCapsuleRPi, explaining how each component works together to provide Time Machine functionality on Raspberry Pi.

## Table of Contents

1. [System Overview](#system-overview)
2. [Samba Server](#samba-server)
3. [vfs_fruit Module](#vfs_fruit-module)
4. [Avahi mDNS/Bonjour](#avahi-mdnsbonjour)
5. [Authentication Model](#authentication-model)
6. [Data Flow](#data-flow)
7. [Performance Considerations](#performance-considerations)
8. [Security Model](#security-model)

---

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         macOS Client                             │
│                    (Time Machine App)                            │
└──────────────────────────────┬──────────────────────────────────┘
                               │
                               │ SMB3 Protocol + AFP announcements
                               │
┌──────────────────────────────▼──────────────────────────────────┐
│                         Raspberry Pi 4                           │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                    Avahi Daemon                           │  │
│  │            (mDNS/Bonjour Service Discovery)               │  │
│  └──────────────────────────────┬───────────────────────────┘  │
│                                 │                               │
│  ┌─────────────────────────────▼────────────────────────────┐  │
│  │                   Samba smbd/nmbd                         │  │
│  │                  (SMB/CIFS Server)                        │  │
│  │                                                             │  │
│  │  ┌────────────────────────────────────────────────────┐  │  │
│  │  │         vfs_fruit + vfs_streams_xattr               │  │  │
│  │  │        (macOS Compatibility Layer)                  │  │  │
│  │  └────────────────────────────────────────────────────┘  │  │
│  └──────────────────────────────┬───────────────────────────┘  │
│                                 │                               │
│  ┌─────────────────────────────▼────────────────────────────┐  │
│  │              ext4 Filesystem                             │  │
│  │           (/mnt/timecapsule)                             │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                   │
└───────────────────────────────────────────────────────────────────┘
                                │
                                │
┌───────────────────────────────▼─────────────────────────────────┐
│                    External USB Drive                            │
│                      (1TB+ Storage)                              │
└───────────────────────────────────────────────────────────────────┘
```

---

## Samba Server

### Role

Samba provides SMB/CIFS file sharing protocol compatibility, allowing macOS to mount the Raspberry Pi's storage as a network volume.

### Key Components

1. **smbd** - The main Samba daemon handling SMB/CIFS connections
2. **nmbd** - NetBIOS name server for network browsing

### Protocol Configuration

```ini
min protocol = SMB2
max protocol = SMB3
server min protocol = SMB2
```

**Why SMB2/3 only?**
- SMB1 is deprecated and insecure (WannaCry exploited SMB1 vulnerabilities)
- macOS Time Machine requires SMB2 or higher
- SMB3 offers encryption and improved performance

### VFS (Virtual File System) Architecture

Samba uses VFS modules to extend functionality:

```ini
vfs objects = catia fruit streams_xattr
```

**Module stack:**
1. **catia** - Character set translation for special characters
2. **fruit** - Time Machine specific functionality
3. **streams_xattr** - Alternate data stream support via extended attributes

---

## vfs_fruit Module

### What is vfs_fruit?

vfs_fruit is a Samba VFS module specifically designed to provide macOS compatibility. It implements Apple's proprietary extensions to the SMB protocol.

### Key Features

#### 1. Time Machine Support

```ini
fruit:time machine = yes
```

Enables Time Machine specific features:
- Sparse bundle support
- Safe backup verification
- Proper ACL handling

#### 2. Alternate Data Streams (ADS)

macOS stores file metadata in "named streams" separate from the main data fork:

```
file.txt
  └── file.txt:AFP_AfpInfo     (Finder metadata)
  └── file.txt:AFP_Resource    (Resource fork)
```

vfs_fruit maps these to Linux extended attributes:

```ini
fruit:metadata = stream
fruit:encoding = native
```

#### 3. Apple Double File Handling

```ini
fruit:veto apple double = no
fruit:delete vacuum files = yes
```

Controls handling of `._` prefix files (AppleDouble format):
- Legacy format for storing resource forks on non-ADS filesystems
- "delete vacuum files" enables automatic cleanup

#### 4. Copyfile Acceleration

```ini
fruit:copyfile = yes
```

Enables Apple's `copyfile()` acceleration for faster file transfers.

#### 5. Quota Management

```ini
fruit:time machine max size = 2T
```

Sets the maximum size for Time Machine backups. macOS respects this limit and will:
- Show warnings when approaching the limit
- Start deleting old backups when limit is reached

### How vfs_fruit Works

```
┌─────────────────────────────────────────────────────────────┐
│                     macOS Request                           │
│  "Write file.txt with metadata to SMB share"                │
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│                   vfs_fruit Module                          │
│                                                             │
│  1. Intercept file write                                    │
│  2. Extract Apple-specific metadata                         │
│  3. Convert to Linux xattr format                           │
│  4. Store data fork on filesystem                           │
│  5. Store metadata as extended attributes                   │
│  6. Return success to macOS                                 │
└────────────────────────────┬────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────┐
│                   ext4 Filesystem                           │
│                                                             │
│  file.txt          (actual file data)                       │
│  user.DosAssigned    (DOS attributes)                       │
│  user.XXX          (macOS metadata in xattr)                │
└─────────────────────────────────────────────────────────────┘
```

---

## Avahi mDNS/Bonjour

### Role

Avahi implements the mDNS (Multicast DNS) and DNS-SD (Service Discovery) protocols, allowing macOS to automatically discover the Time Capsule on the network.

### How mDNS Works

1. **Hostname Resolution**
   - Devices on local network broadcast queries
   - Each device responds to queries for its own hostname
   - Example: `ping pi4.local` resolves without a DNS server

2. **Service Discovery**
   - Devices broadcast services they provide
   - Clients browse for specific service types
   - Example: macOS browses for `_smb._tcp` services

### Service Configuration

Our Avahi service file advertises three services:

```xml
<!-- SMB file sharing -->
<service>
    <type>_smb._tcp</type>
    <port>445</port>
</service>

<!-- Device information -->
<service>
    <type>_device-info._tcp</type>
    <txt-record>model=TimeCapsule</txt-record>
</service>

<!-- AFP/Time Machine advertisement -->
<service>
    <type>_adisk._tcp</type>
    <txt-record>dk0=adVN=TimeCapsule,adVF=0x82</txt-record>
</service>
```

### TXT Record Breakdown

**_adisk._tcp records:**

| Record | Meaning |
|--------|---------|
| `dk0` | Disk zero (first disk) |
| `adVN` | AFP Volume Name (share name) |
| `adVF=0x82` | Volume flags (0x82 = supports Time Machine + supports ACLs) |
| `sys=waMA=XX:XX:XX:XX:XX:XX` | Wake-on-LAN MAC address |

### Discovery Flow

```
┌──────────────────┐           mDNS Broadcast            ┌──────────────────┐
│      macOS       │ ──────────────────────────────────> │   Raspberry Pi   │
│                  │ "Who provides _smb._tcp service?"   │                  │
└──────────────────┘                                    └──────────────────┘
      ▲                                                           │
      │                                                           │ mDNS Response
      │                                                           │ "I'm pi4.local,
      │                                                           │  SMB on port 445"
      │                                                           ▼
┌──────────────────┐                                   ┌──────────────────┐
│   Finder shows   │ <────────────────────────────────── │                  │
│  "TIMECAPSULE-"  │         Auto-appears in sidebar     │                  │
│     "PI4"        │                                    └──────────────────┘
└──────────────────┘
```

---

## Authentication Model

### Security Architecture

```
┌──────────────────────────────────────────────────────────┐
│                    Authentication Flow                    │
└──────────────────────────────────────────────────────────┘

1. macOS connects to smb://pi4.local/TimeCapsule
   │
2. Samba requests username/password
   │
3. User enters credentials
   │
4. Samba validates against TDB password database
   │
   ├─── Valid user? ──> Check "valid users" in smb.conf
   │                        │
   │                        └──> User owns share path?
   │                                │
   │                                └──> Grant access
   │
   └─── Invalid? ──> Deny access
```

### Password Storage

Samba uses TDB (Trivial Database) for password storage:

```ini
passdb backend = tdbsam
```

- Location: `/var/lib/samba/passdb.tdb`
- Format: Hashed passwords (not plain text)
- Separate from Linux system passwords (`/etc/shadow`)

### User Management

```bash
# Create Samba user
smbpasswd -a username

# Enable user
smbpasswd -e username

# Disable user
smbpasswd -d username

# Delete user
smbpasswd -x username
```

### Why Separate Authentication?

1. **Isolation**: Samba compromise doesn't expose system passwords
2. **Flexibility**: Different users for different services
3. **SMB-specific**: Samba passwords can be different from Linux passwords

---

## Data Flow

### Initial Backup Flow

```
┌──────────────────────────────────────────────────────────────────┐
│                     Time Machine Initial Backup                  │
└──────────────────────────────────────────────────────────────────┘

macOS                                    Raspberry Pi
  │                                          │
  │  1. Scan files for backup                │
  ├─────────────────────────────────────────>│
  │                                          │
  │  2. Calculate checksums                  │
  │     (determine changed files)            │
  │                                          │
  │  3. Create sparse bundle disk image      │
  │     (TimeCapsule.sparsebundle)           │
  ├─────────────────────────────────────────>│
  │                                          │  4. Create directory structure
  │                                          │     /mnt/timecapsule/
  │                                          │       └── TimeCapsule.sparsebundle/
  │                                          │           ├── token (file size)
  │                                          │           ├── bands/ (data)
  │                                          │           └── com.apple.TimeMachine.SnapshotFile
  │                                          │
  │  5. Write backup data                    │
  │     (compressed, deduplicated)           │
  ├─────────────────────────────────────────>│
  │                                          │
  │  6. Write metadata                       │
  │     (via AFP_AfpInfo stream)             │
  ├─────────────────────────────────────────>│
  │                                          │  7. Store as xattr
  │                                          │
  │  8. Verify backup integrity              │
  ├─────────────────────────────────────────>│
  │                                          │
  │  9. Complete                             │
  │<─────────────────────────────────────────│
```

### Incremental Backup Flow

```
┌──────────────────────────────────────────────────────────────────┐
│                    Incremental Backup (Hourly)                   │
└──────────────────────────────────────────────────────────────────┘

macOS                                    Raspberry Pi
  │                                          │
  │  1. FSEvents tells TM what changed       │
  │     (file system events log)             │
  │                                          │
  │  2. Calculate hard link tree             │
  │     (unchanged files = hard links)       │
  │                                          │
  │  3. Write only changed blocks            │
  ├─────────────────────────────────────────>│  4. Append to sparse bundle
  │                                          │
  │  5. Update catalog                       │
  ├─────────────────────────────────────────>│  6. Update metadata
  │                                          │
  │  7. Complete (much faster than initial)  │
  │<─────────────────────────────────────────│
```

### Sparse Bundle Structure

```
TimeCapsule.sparsebundle/
├── token                                    # Actual disk size
├── bands/                                   # Data bands (8MB each)
│   ├── 0                                   # Band file 0
│   ├── 1                                   # Band file 1
│   ├── 2                                   # Band file 2
│   └── ...                                 # More bands...
├── com.apple.TimeMachine.SnapshotFile      # Snapshot metadata
└── Info.plist                              # Bundle properties
```

**Why sparse bundles?**
- Can grow as needed (up to quota limit)
- Efficient storage (only used space is allocated)
- Can be mounted as HFS+ filesystem
- Supports hard links for incremental backups

---

## Performance Considerations

### Network Bottlenecks

| Component | Theoretical Max | Real-World Performance |
|-----------|-----------------|------------------------|
| **Gigabit Ethernet** | 125 MB/s | ~100 MB/s (Pi 4) |
| **USB 3.0** | 625 MB/s | ~40 MB/s (external drive) |
| **WiFi (2.4GHz)** | 30-50 MB/s | ~5-10 MB/s (real-world) |
| **WiFi (5GHz)** | 100-150 MB/s | ~20-40 MB/s (real-world) |

### Samba Tuning

```ini
# Raw I/O (bypass buffer cache)
read raw = yes
write raw = yes

# Async I/O
aio read size = 16384
aio write size = 16384
```

### Filesystem Considerations

**Why ext4?**
- Native Linux filesystem (no FUSE overhead)
- Journaling for data integrity
- Extended attributes support (required for vfs_fruit)
- Excellent performance on Raspberry Pi

**Alternatives considered:**
- **NTFS**: Poor Linux performance, no xattr support
- **FAT32**: No permissions, 4GB file limit
- **exFAT**: No permissions, limited xattr support
- **Btrfs**: Too much overhead for Pi 4

### First Backup Optimization

First backup is always slow due to:
1. Full data transfer
2. Compression overhead
3. Sparse bundle creation

**Tips to speed up:**
- Use Ethernet instead of WiFi
- Exclude unnecessary folders (System, Caches)
- Run overnight when not using Mac

---

## Security Model

### Transport Security

```
┌───────────────────────────────────────────────────────────┐
│                   Security Layers                          │
└───────────────────────────────────────────────────────────┘

Application:  Time Machine (encrypted backups)
     │
Protocol:     SMB3 with encryption (optional)
     │
Authentication: User password (stored hashed)
     │
Filesystem:   ext4 with Unix permissions (770)
     │
Network:      Local network or VPN (Tailscale)
```

### SMB3 Encryption

Samba supports SMB3 encryption:

```ini
# To enable (add to [global] section)
server smb encrypt = desired    # or required
smb encrypt = required
```

**Trade-offs:**
- ✅ Encrypts data in transit
- ❌ CPU overhead on Raspberry Pi
- ❌ May reduce transfer speed by ~20%

### Firewall Considerations

Required ports:

| Port | Protocol | Service |
|------|----------|---------|
| 445 | TCP | SMB (Samba) |
| 137-139 | TCP/UDP | NetBIOS (optional) |
| 5353 | UDP | mDNS (Avahi) |

UFW example:

```bash
sudo ufw allow from 192.168.1.0/24 to any port 445
sudo ufw allow from 192.168.1.0/24 to any port 5353/udp
```

### Remote Access via Tailscale

```
┌──────────────────┐        Tailscale VPN        ┌──────────────────┐
│  Mac (remote)    │ ──────────────────────────> │  Raspberry Pi    │
│                  │    (encrypted tunnel)      │                  │
│  smb://100.x.y.z │                            │  :445 (SMB)       │
└──────────────────┘                              └──────────────────┘
```

**Benefits:**
- End-to-end encryption
- No port forwarding required
- Works from anywhere
- Built-in authentication

---

## Troubleshooting Architecture

### Log Locations

| Service | Log Location |
|---------|--------------|
| **Samba** | `/var/log/samba/log.smbd`, `/var/log/samba/` |
| **Avahi** | `/var/log/syslog` (grep avahi) |
| **System** | `journalctl -u smbd`, `journalctl -u avahi-daemon` |
| **Kernel** | `dmesg` (for USB/Storage issues) |

### Common Failure Points

1. **vfs_fruit not loaded**
   - Symptom: Share mounts but Time Machine fails
   - Check: `smbd -b \| grep vfs_fruit`
   - Fix: Install Samba 4.x from official repos

2. **Drive not mounted**
   - Symptom: Connection refused
   - Check: `df -h \| grep timecapsule`
   - Fix: Check fstab, verify UUID

3. **Permissions error**
   - Symptom: "You do not have permission"
   - Check: `ls -la /mnt/timecapsule`
   - Fix: `chown -R user:user /mnt/timecapsule`

4. **Avahi not advertising**
   - Symptom: Server doesn't appear in Finder
   - Check: `avahi-browse -a --terminate`
   - Fix: Restart avahi-daemon

---

## References

- [Samba vfs_fruit Documentation](https://www.samba.org/samba/docs/current/man-html/vfs_fruit.8.html)
- [Apple Time Machine Technical Overview](https://developer.apple.com/support/time-machine/)
- [Avahi Service Discovery](https://avahi.org/)
- [Raspberry Pi Performance Tuning](https://www.raspberrypi.com/documentation/computers/configuration.html)

---

**Document Version:** 1.0
**Last Updated:** 2026-02-01
