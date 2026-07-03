# TimeCapsule-Pi - Turn your Raspberry Pi into a Time Machine Server

A complete, production-ready solution to transform a Raspberry Pi (3B+/4/5) into a **Time Machine backup server** for macOS, replacing the need for an expensive Apple Time Capsule.

![Raspberry Pi](https://img.shields.io/badge/Raspberry%20Pi-3%2B%204%2B%205-red)
![Samba](https://img.shields.io/badge/Samba-4.13+-blue)
![macOS](https://img.shields.io/badge/macOS-Time%20Machine-success)
![License](https://img.shields.io/badge/License-MIT-green)

## Why Raspberry Pi?

| Advantage | Details |
|-----------|---------|
| ✅ **Always-on** | Can run 24/7 with minimal power consumption (~5-10W) |
| ✅ **Cost-effective** | Hardware you may already own, no expensive Apple hardware |
| ✅ **Full control** | Configure exactly what you need, no vendor limitations |
| ✅ **Samba 4.x** | Complete vfs_fruit module support for Time Machine |
| ✅ **USB 3.0** | Fast transfer speeds for external drives |
| ✅ **Network accessible** | Works on your local network and remotely via Tailscale VPN |
| ✅ **Open source** | Based on standard Linux technologies (Samba, Avahi) |

## Features

- **Automated setup** - Single script installation
- **macOS auto-discovery** - Appears natively in Time Machine preferences
- **SMB3 protocol** - Secure and fast transfers
- **vfs_fruit support** - Full macOS compatibility
- **User authentication** - Secure password-based access
- **mDNS/Bonjour** - Zero-configuration network discovery
- **Tailscale ready** - Works over VPN for remote backups

## Hardware Requirements

- **Raspberry Pi 4** (4GB+ RAM recommended, Pi 3B+ works too)
- **External USB drive** (1TB+ recommended, formatted as ext4)
- **Network connection** (Ethernet preferred, WiFi works)
- **Power supply** - Reliable 5V/3A for Pi 4

## Software Requirements

- **Raspberry Pi OS** (Bullseye or Bookworm recommended)
- **SSH access** to your Raspberry Pi
- **macOS 10.9+** (Mavericks or newer for Time Machine support)

## Quick Start

### Option 1: Automated Installation (Recommended)

1. **Clone this repository:**
   ```bash
   git clone https://github.com/rizal72/TimeCapsule-Pi.git
   cd TimeCapsule-Pi
   ```

2. **Connect your external drive** to the Raspberry Pi

3. **Run the installer:**
   ```bash
   chmod +x install.sh
   sudo ./install.sh
   ```

4. **Follow the prompts** - the script will:
   - Detect your external drive
   - Format it as ext4 (with confirmation)
   - Install and configure Samba
   - Set up Avahi for macOS discovery
   - Create a user account for Time Machine
   - Configure auto-mount on boot

5. **On your Mac:** Open System Settings → General → Time Machine → Add Backup Disk
   - Select **TIMECAPSULE-PI** → **TimeCapsule**
   - Enter your credentials
   - Start your first backup!

### Option 2: Manual Installation

See [MANUAL_INSTALL.md](MANUAL_INSTALL.md) for detailed step-by-step instructions.

## Configuration

### Default Settings

After installation, your Time Capsule will be configured as:

| Setting | Value |
|---------|-------|
| **Server name** | `TIMECAPSULE-PI` |
| **Share name** | `TimeCapsule` |
| **Protocol** | SMB3 (SMB2/3 forced, SMB1 disabled) |
 | **Quota** | 1TB (configurable) |
| **Authentication** | User-based (no guest access) |

### Customization

Edit `/etc/samba/smb.conf` to customize:

```ini
[TimeCapsule]
    comment = Time Machine Backup on Raspberry Pi
    path = /mnt/timecapsule
    browseable = yes
    read only = no
    valid users = your_username

    # Time Machine specific
    fruit:time machine max size = 2T    # Change quota here
    vfs objects = catia fruit streams_xattr
```

Restart Samba after changes:
```bash
sudo systemctl restart smbd nmbd
```

## Performance Tips

1. **Use Ethernet** instead of WiFi for faster backups
2. **USB 3.0 drive** - Use a USB 3.0 port on your Pi 4
3. **First backup** will take longer (several hours for large data sets)
4. **Subsequent backups** are incremental and much faster

## Troubleshooting

### Share not visible on Mac

1. Check Samba is running:
   ```bash
   systemctl status smbd nmbd
   ```

2. Check Avahi is running:
   ```bash
   systemctl status avahi-daemon
   ```

3. Restart services:
   ```bash
   sudo systemctl restart smbd nmbd avahi-daemon
   ```

### Connection refused

1. Verify firewall rules allow SMB (port 445)
2. Check network connectivity:
   ```bash
   ping pi4.local
   ```

### Permission errors

1. Check disk is mounted:
   ```bash
   df -h | grep timecapsule
   ```

2. Verify permissions:
   ```bash
   ls -la /mnt/timecapsule
   ```

3. The installer should set correct permissions automatically

## Advanced Usage

### Tailscale Remote Access

Your Time Capsule works over Tailscale VPN, allowing backups from anywhere -- and it also works when you are on the same local network, so you can use a single address everywhere.

#### 1. Install Tailscale on the Pi

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
```

#### 2. Allow Tailscale connections in Samba

**Important:** If you installed TimeCapsule-Pi with a version before July 2026, Samba may be configured to only listen on your local network. To allow connections via Tailscale, edit `/etc/samba/smb.conf` and remove (or comment out) these lines:

```ini
# bind interfaces only = yes
# interfaces = 127.0.0.1 192.168.1.0/24
```

Then restart Samba:

```bash
sudo systemctl restart smbd nmbd
```

New installations from `install.sh` after July 2026 already include this fix.

#### 3. Find the MagicDNS hostname

Tailscale provides a stable hostname that works both remotely and on your local network:

```bash
tailscale status
# Look for your Pi's name, e.g. pi4
```

The full MagicDNS hostname is `<hostname>.<tailnet>.ts.net`. To find yours:

```bash
tailscale status --json | grep MagicDNSSuffix
# Example output: "MagicDNSSuffix": "tail9350d7.ts.net"
# Your Pi's address: pi4.tail9350d7.ts.net
```

#### 4. Connect from your Mac

From anywhere (home or away), use **Cmd+K** in Finder:

```
smb://<your-pi-hostname>.tailnet.ts.net/TimeCapsule
```

For example: `smb://pi4.tail9350d7.ts.net/TimeCapsule`

Enter your Samba username and password -- the same credentials you use locally.

#### 5. Existing backups are preserved

When you switch from a local address (e.g. `smb://TIMECAPSULE-PI.local`) to the Tailscale hostname, Time Machine will detect your existing `.sparsebundle` on the share and continue using it. The first backup via Tailscale may show a long "Preparing" phase -- this is normal, Time Machine is verifying the existing sparsebundle integrity, not re-uploading everything. Subsequent backups will be incremental.

#### 6. Use one address everywhere

Because the Tailscale MagicDNS hostname resolves both locally (direct connection) and remotely (via Tailscale), you can set it as your **only** Time Machine backup destination and forget about switching addresses when you change location.

### Multiple Users

Create additional Samba users:
```bash
sudo smbpasswd -a newusername
```

Then add them to `valid users` in `/etc/samba/smb.conf`.

## Project Structure

```
TimeCapsule-Pi/
├── README.md              # This file
├── README.it.md           # Italian documentation
├── CLAUDE.md              # AI assistant guidelines
├── MANUAL_INSTALL.md      # Detailed manual setup guide
├── install.sh             # Automated installer script
├── setup/
│   ├── smb.conf           # Samba configuration template
│   └── timecapsule.service  # Avahi mDNS service file
└── docs/
    ├── architecture.md    # Technical details
    └── troubleshooting.md # Common issues and solutions
```

## Acknowledgments

- **Samba Project** - Excellent SMB server implementation
- **Avahi Project** - mDNS/Bonjour for Linux
- **Raspberry Pi Foundation** - Amazing little computer

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

This project is provided as-is for educational and personal use.

## Author

**Riccardo Sallusti**

- GitHub: [@rizal72](https://github.com/rizal72)
- Project started: February 2026

---

**Note:** This project replaces expensive Apple Time Capsule hardware with a configurable, open-source solution based on Raspberry Pi. It's been tested and confirmed working on macOS Tahoe 26.2 with Raspberry Pi 4 running Raspberry Pi OS Bullseye.

## Disclaimer

This software is provided "as is", without warranty of any kind. Always keep multiple backups of important data. The authors are not responsible for any data loss.
