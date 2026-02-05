# AGENTS.md - Guidelines for Agentic Coding Assistants

This file provides coding conventions and guidelines for TimeCapsule-Pi, a Raspberry Pi-based Time Machine backup server.

## Project Overview

**Technology Stack:**
- **Language:** Bash scripting
- **Configuration:** INI (Samba), XML (Avahi)
- **Target OS:** Raspberry Pi OS (Debian-based)
- **Services:** Samba, Avahi
- **No:** build system, automated tests, package managers

## Commands

### No Build/Lint/Test Framework
This project uses shell scripts and configuration files. No automated build, lint, or test commands exist.

### Manual Testing Commands
```bash
# Validate Samba configuration
testparm

# Check Samba version and vfs_fruit support
smbd --version
smbd -b | grep vfs_fruit

# Check service status
systemctl status smbd nmbd avahi-daemon

# Test Samba share locally
smbclient -L localhost -U username

# List available Samba shares
smbclient -L localhost -U username% -c 2>/dev/null

# Check mount point
mountpoint -q /mnt/timecapsule
df -h | grep timecapsule

# Browse Avahi services
avahi-browse -a --terminate

# Check USB drives
lsblk
lsusb
```

### Testing Single Functions in install.sh
To test specific functions manually:
```bash
# Source the script to access functions
source ./install.sh

# Call individual functions (may require root)
check_system
detect_usb_drives
```

## Code Style Guidelines

### Shell Scripting (Bash)

**Shebang & Strict Mode:**
```bash
#!/bin/bash
set -e  # Always include - exit on error
```

**Color Output Constants:**
```bash
# Define colors at script start
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'  # No Color (reset)
```

**Function Naming:**
- Use `snake_case` for all function names
- Descriptive names: `print_header`, `check_root`, `configure_samba`
- Group related functions together

**Output Functions:**
```bash
# Standard output helpers (use these consistently)
print_header() {
    echo -e "${BLUE}...${NC}"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# User confirmation prompt
confirm() {
    read -p "$(echo -e ${GREEN}[PROMPT]${NC} $1 [y/N]: )" response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}
```

**Variable Naming:**
- Constants: `UPPER_SNAKE_CASE` (e.g., `MOUNT_POINT`, `QUOTA_SIZE`)
- Local variables: `lower_snake_case` (e.g., `tm_user`, `partition`)
- Always quote variables: `"$variable"` to handle spaces

**Error Handling:**
```bash
# Always use set -e at script start
set -e

# Check for root privileges
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (sudo)"
        exit 1
    fi
}

# Validate commands before use
if ! command -v apt &>/dev/null; then
    print_error "apt package manager not found"
    exit 1
fi
```

**Conditional Logic:**
```bash
# Use [[ ]] for Bash conditions (more reliable than [ ])
if [[ "$os_id" != "raspbian" ]]; then
    print_warning "Not running on Raspbian"
fi

# Check array length
if [[ ${#drives[@]} -eq 0 ]]; then
    print_error "No drives found"
fi

# Numeric comparison
if [[ $mem_total -lt 512 ]]; then
    print_warning "Low memory detected"
fi
```

**Command Execution:**
```bash
# Redirect stderr to suppress noise
apt update 2>/dev/null

# Check command success with if
if mountpoint -q "$MOUNT_POINT"; then
    print_info "Drive is mounted"
fi

# Use || true to ignore expected failures
umount "$mount" 2>/dev/null || true
```

**User Input:**
```bash
# Prompt for input with validation
while true; do
    read -p "$(echo -e ${GREEN}[PROMPT]${NC} Enter choice: )" choice
    if [[ "$choice" =~ ^[0-9]+$ ]]; then
        break
    else
        print_error "Invalid input"
    fi
done
```

**Comments:**
- Use `#` for single-line comments
- Add block comments for sections
- Document non-obvious commands
- Include usage example at script start:
```bash
################################################################################
# TimeCapsule-Pi - Automated Installation Script
# Transforms Raspberry Pi into a Time Machine backup server for macOS
#
# Usage: sudo ./install.sh
################################################################################
```

### Configuration Files (INI Format - smb.conf)

**Structure:**
```ini
[section_name]
    # Comment explaining this section
    parameter = value
    parameter_with_spaces = value
```

**Conventions:**
- Use 4 spaces for indentation (not tabs)
- Comments on their own lines
- Parameter-value pairs aligned
- Group related parameters together
- Empty lines between logical sections

**Template Guidelines:**
- Use placeholders like `valid users = username` for user-specific values
- Include comprehensive comments for Time Machine options
- Keep backup of existing config before overwriting

### Configuration Files (XML Format - Avahi)

**Structure:**
```xml
<?xml version="1.0" standalone='no'?><!--*-nxml-*-->
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">

<!-- Multi-line comment explaining purpose -->
<service-group>
  <tag>value</tag>
  <!-- Inline comment -->
</service-group>
```

**Conventions:**
- Indent with 2 spaces
- Comments explaining each service block
- Replace MAC addresses with placeholders: `xx:xx:xx:xx:xx:xx`
- Include file location comment at top

## Naming Conventions

**Files:**
- Shell scripts: `lowercase.sh` (e.g., `install.sh`)
- Configuration: `lowercase.ext` (e.g., `smb.conf`, `timecapsule.service`)
- Documentation: `UPPERCASE.md` (e.g., `README.md`, `ARCHITECTURE.md`)

**Shell Functions:** `snake_case` (e.g., `check_system`, `format_drive`)

**Variables:**
- Constants: `UPPER_SNAKE_CASE` (e.g., `MOUNT_POINT`, `QUOTA_SIZE`)
- Local variables: `lower_snake_case` (e.g., `tm_user`, `partition`, `uuid`)

**Samba Shares:** `TitleCase` (e.g., `[TimeCapsule]`)

**Service Names:** `lowercase` (e.g., `timecapsule.service`)

## Error Handling

**Exit on Error:**
- Always use `set -e` at script start
- Use `exit 1` for critical failures
- Use `exit 0` for successful early exits

**User Confirmation:**
- Use `confirm()` before destructive operations (formatting, overwriting)
- Provide clear warning messages
- Allow user to cancel safely

**Validation:**
- Check prerequisites before proceeding
- Validate user input (numeric ranges, file existence)
- Test configuration files before deploying

**Logging:**
- Use colored output helpers for clarity
- Log critical steps with `print_step`
- Use `print_info` for progress updates
- Use `print_error` for failures
- Use `print_warning` for non-critical issues

## File Organization

```
TimeCapsule-Pi/
├── README.md              # Main documentation (English)
├── MANUAL_INSTALL.md      # Manual setup guide
├── install.sh            # Main installer script
├── setup/
│   ├── smb.conf          # Samba configuration template
│   └── timecapsule.service  # Avahi service template
└── docs/
    ├── architecture.md    # Technical architecture
    └── troubleshooting.md  # Common issues
```

## Common Patterns

**Drive Detection:**
```bash
# Use lsblk for drive enumeration
lsblk -d -n -o NAME,MODEL,SIZE,TRAN | grep -E "usb|sdb"
```

**UUID Retrieval:**
```bash
# Always use UUID for fstab entries (stable across reboots)
uuid=$(blkid -s UUID -o value "$partition")
```

**Service Management:**
```bash
# Standard restart + enable pattern
systemctl restart service_name
systemctl enable service_name

# Check status without pager
systemctl status service_name --no-pager
```

**File Backup:**
```bash
# Timestamped backups before modification
backup_file="/etc/file.conf.backup.$(date +%Y%m%d_%H%M%S)"
cp /etc/file.conf "$backup_file"
```

**Configuration Testing:**
```bash
# Test Samba config before restart
testparm -s /etc/samba/smb.conf > /dev/null 2>&1
```

## Security Best Practices

- Always verify destructive operations (formatting, deletion) with user confirmation
- Never hardcode passwords (prompt user or use Samba's smbpasswd)
- Use `valid users` to restrict access (no `guest ok = yes`)
- Force SMB2/3 (disable SMB1 for security)
- Use UUIDs in fstab (stable, device-independent)
- Set appropriate file permissions (770 for TimeCapsule directory)

## Testing Guidelines

When modifying `install.sh`:
1. Test functions individually if possible
2. Use `testparm` to validate Samba config changes
3. Verify service status after configuration: `systemctl status smbd nmbd avahi-daemon`
4. Check mount point: `df -h | grep timecapsule`
5. Test Samba share locally: `smbclient -L localhost -U username`

## Important Notes

- This is a shell scripting project with no automated tests
- Testing is manual via service status checks and Samba utilities
- Configuration files are templates for `/etc/` production files
- Always maintain backward compatibility with existing installations
- Documentation must be in English (README.md)
- User-specific values (username, MAC address) should be placeholders in templates
