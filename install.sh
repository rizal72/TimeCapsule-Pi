#!/bin/bash
################################################################################
# TimeCapsule-Pi - Automated Installation Script
# Transforms Raspberry Pi into a Time Machine backup server for macOS
#
# Usage: sudo ./install.sh
################################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration variables
MOUNT_POINT="/mnt/timecapsule"
SHARE_NAME="TimeCapsule"
SERVICE_NAME="timecapsule"
QUOTA_SIZE="2T"

# Functions
print_header() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}        ${GREEN}TimeCapsule-Pi - Automated Installer${NC}            ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo
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

confirm() {
    read -p "$(echo -e ${GREEN}[PROMPT]${NC} $1 [y/N]: )" response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (sudo)"
        exit 1
    fi
}

# Detect connected USB drives
detect_usb_drives() {
    print_step "Detecting USB drives..."

    # Get list of USB drives (excluding system drive)
    local drives=($(lsblk -d -n -o NAME,MODEL,SIZE,TRAN | grep -v "sda" | grep -E "usb|sdb|sdc|sdd|sde|sdf" | awk '{print $1}'))

    if [[ ${#drives[@]} -eq 0 ]]; then
        print_error "No USB drives detected!"
        print_info "Please connect your external USB drive and run the script again."
        exit 1
    fi

    echo -e "\n${GREEN}Available USB drives:${NC}"
    local i=1
    for drive in "${drives[@]}"; do
        local info=$(lsblk -d -n -o NAME,MODEL,SIZE,TRAN "/dev/$drive" 2>/dev/null || echo "$drive (unknown)")
        echo "  [$i] /dev/$drive - $info"
        ((i++))
    done
    echo

    # Prompt for drive selection
    while true; do
        read -p "$(echo -e ${GREEN}[PROMPT]${NC} Select drive number [1-${#drives[@]}]: )" drive_num

        if [[ "$drive_num" =~ ^[0-9]+$ ]] && [[ $drive_num -ge 1 ]] && [[ $drive_num -le ${#drives[@]} ]]; then
            SELECTED_DRIVE="/dev/${drives[$((drive_num-1))]}"
            break
        else
            print_error "Invalid selection. Please enter a number between 1 and ${#drives[@]}"
        fi
    done

    print_info "Selected drive: $SELECTED_DRIVE"

    # Show drive details
    echo -e "\n${YELLOW}Drive details:${NC}"
    lsblk "$SELECTED_DRIVE"
    echo

    # Confirm format
    if ! confirm "This will ERASE ALL DATA on $SELECTED_DRIVE. Continue?"; then
        print_info "Installation cancelled by user."
        exit 0
    fi
}

# Check system requirements
check_system() {
    print_step "Checking system requirements..."

    # Check OS
    if [[ ! -f /etc/os-release ]]; then
        print_error "Cannot detect OS. This script requires Raspberry Pi OS."
        exit 1
    fi

    local os_id=$(grep "^ID=" /etc/os-release | cut -d'=' -f2)
    if [[ "$os_id" != "raspbian" ]] && [[ "$os_id" != "debian" ]]; then
        print_warning "This script is designed for Raspberry Pi OS (Debian)."
        if ! confirm "Continue anyway?"; then
            exit 0
        fi
    fi

    # Check available memory
    local mem_total=$(free -m | awk '/^Mem:/{print $2}')
    print_info "Total RAM: ${mem_total}MB"

    if [[ $mem_total -lt 512 ]]; then
        print_warning "Low memory detected. 1GB+ RAM recommended."
    fi

    # Check disk space
    local disk_free=$(df -m / | tail -1 | awk '{print $4}')
    print_info "Free disk space: ${disk_free}MB"

    if [[ $disk_free -lt 500 ]]; then
        print_error "Insufficient disk space. At least 500MB required."
        exit 1
    fi
}

# Install required packages
install_packages() {
    print_step "Installing required packages..."

    apt update

    # Install Samba and Avahi
    apt install -y samba samba-common-bin avahi-daemon

    # Check Samba version
    local samba_version=$(smbd --version)
    print_info "Samba version: $samba_version"

    # Check vfs_fruit support
    if smbd -b | grep -q VFS_MODULE_FRUIT; then
        print_info "vfs_fruit module: supported"
    else
        print_error "vfs_fruit module NOT found. Time Machine requires this module."
        exit 1
    fi
}

# Get username for Time Machine
get_username() {
    print_step "Setting up Time Machine user..."

    echo
    echo "Options:"
    echo "  1) Create new user (timemachine)"
    echo "  2) Use existing system user"
    echo

    while true; do
        read -p "$(echo -e ${GREEN}[PROMPT]${NC} Choose option [1/2]: )" user_choice

        case $user_choice in
            1)
                TM_USER="timemachine"
                print_info "Creating new user: $TM_USER"

                # Create user without home directory
                adduser --no-create-home --gecos "" "$TM_USER" <<EOF



EOF
                break
                ;;
            2)
                read -p "$(echo -e ${GREEN}[PROMPT]${NC} Enter existing username: )" TM_USER
                if id "$TM_USER" &>/dev/null; then
                    print_info "Using existing user: $TM_USER"
                    break
                else
                    print_error "User '$TM_USER' does not exist."
                fi
                ;;
            *)
                print_error "Invalid option. Choose 1 or 2."
                ;;
        esac
    done

    # Set Samba password
    while true; do
        smbpasswd -a "$TM_USER"
        if [[ $? -eq 0 ]]; then
            break
        fi
        print_warning "Failed to set Samba password. Try again."
    done

    # Enable user
    smbpasswd -e "$TM_USER"
    print_info "Samba user '$TM_USER' created and enabled."
}

# Format drive
format_drive() {
    print_step "Formatting drive as ext4..."

    print_warning "Partitioning $SELECTED_DRIVE..."

    # Unmount if mounted
    for mount in $(mount | grep "^${SELECTED_DRIVE}" | awk '{print $1}'); do
        umount "$mount" 2>/dev/null || true
    done

    # Create new partition table
    print_info "Creating partition table..."
    fdisk "$SELECTED_DRIVE" <<EOF
o
n
p
1


t
83
w
EOF

    # Wait for device to settle
    sleep 2

    local partition="${SELECTED_DRIVE}1"

    # Format as ext4
    print_info "Formatting ${partition} as ext4..."
    mkfs.ext4 -L TimeCapsule "$partition"

    print_info "Drive formatted successfully."
}

# Setup mount point
setup_mount() {
    print_step "Setting up auto-mount..."

    local partition="${SELECTED_DRIVE}1"

    # Create mount point
    print_info "Creating mount point: $MOUNT_POINT"
    mkdir -p "$MOUNT_POINT"

    # Get UUID
    local uuid=$(blkid -s UUID -o value "$partition")

    if [[ -z "$uuid" ]]; then
        print_error "Cannot get UUID for $partition"
        exit 1
    fi

    print_info "Partition UUID: $uuid"

    # Add to fstab
    local fstab_entry="UUID=$uuid $MOUNT_POINT ext4 defaults,noatime 0 2"

    if grep -q "$uuid" /etc/fstab; then
        print_warning "fstab entry already exists. Updating..."
        sed -i "s|UUID=$uuid.*|$fstab_entry|" /etc/fstab
    else
        print_info "Adding entry to /etc/fstab..."
        echo "$fstab_entry" >> /etc/fstab
    fi

    # Mount the drive
    print_info "Mounting drive..."
    mount -a

    if ! mountpoint -q "$MOUNT_POINT"; then
        print_error "Failed to mount drive."
        exit 1
    fi

    # Set permissions
    print_info "Setting permissions..."
    chown -R "$TM_USER:$TM_USER" "$MOUNT_POINT"
    chmod -R 770 "$MOUNT_POINT"

    print_info "Drive mounted at $MOUNT_POINT"
}

# Configure Samba
configure_samba() {
    print_step "Configuring Samba..."

    # Backup existing config
    if [[ -f /etc/samba/smb.conf ]]; then
        local backup_file="/etc/samba/smb.conf.backup.$(date +%Y%m%d_%H%M%S)"
        cp /etc/samba/smb.conf "$backup_file"
        print_info "Backed up existing config to: $backup_file"
    fi

    # Check if template exists
    if [[ -f "$(dirname "$0")/setup/smb.conf" ]]; then
        print_info "Using Samba configuration template..."
        cp "$(dirname "$0")/setup/smb.conf" /etc/samba/smb.conf
    else
        print_warning "Template not found. Creating basic configuration..."
        create_smb_conf
    fi

    # Update valid users
    sed -i "s/valid users = .*/valid users = $TM_USER/" /etc/samba/smb.conf

    # Test configuration
    print_info "Testing Samba configuration..."
    if ! testparm -s /etc/samba/smb.conf > /dev/null 2>&1; then
        print_error "Samba configuration test failed!"
        exit 1
    fi

    # Restart Samba
    print_info "Restarting Samba..."
    systemctl restart smbd nmbd
    systemctl enable smbd nmbd

    print_info "Samba configured and started."
}

# Create basic Samba configuration (fallback)
create_smb_conf() {
    cat > /etc/samba/smb.conf <<EOF
[global]
    server string = Raspberry Pi 4 Time Machine
    workgroup = WORKGROUP
    netbios name = TIMECAPSULE-PI

    log file = /var/log/samba/log.%m
    max log size = 1000
    log level = 2

    min protocol = SMB2
    max protocol = SMB3

    fruit:time machine = yes
    fruit:delete vacuum files = yes
    fruit:veto apple double = no
    fruit:metadata = stream
    fruit:encoding = native
    fruit:copyfile = yes
    fruit:model = TimeCapsule

    vfs objects = catia fruit streams_xattr

    security = user
    passdb backend = tdbsam
    encrypt passwords = yes

    read raw = yes
    write raw = yes

    bind interfaces only = yes
    interfaces = 127.0.0.1 192.168.1.0/24

[$SHARE_NAME]
    comment = Time Machine Backup on Pi4
    path = $MOUNT_POINT
    browseable = yes
    read only = no
    create mask = 0666
    directory mask = 0777
    guest ok = no
    valid users = $TM_USER

    fruit:time machine max size = $QUOTA_SIZE
    vfs objects = catia fruit streams_xattr
EOF
}

# Configure Avahi
configure_avahi() {
    print_step "Configuring Avahi service discovery..."

    # Get MAC address for adisk record
    local mac_addr=$(ip link show eth0 | awk '/ether/{print $2}')

    if [[ -z "$mac_addr" ]]; then
        mac_addr=$(ip link show | awk '/ether/{print $2; exit}')
    fi

    print_info "Ethernet MAC: $mac_addr"

    # Create Avahi service file
    cat > /etc/avahi/services/${SERVICE_NAME}.service <<EOF
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
    <txt-record>dk0=adVN=${SHARE_NAME},adVF=0x82</txt-record>
    <txt-record>sys=waMA=${mac_addr}</txt-record>
  </service>
</service-group>
EOF

    # Restart Avahi
    print_info "Restarting Avahi..."
    systemctl restart avahi-daemon
    systemctl enable avahi-daemon

    print_info "Avahi configured and started."
}

# Run tests
run_tests() {
    print_step "Running tests..."

    # Test 1: Check services
    print_info "Checking services..."
    if systemctl is-active --quiet smbd && systemctl is-active --quiet nmbd && systemctl is-active --quiet avahi-daemon; then
        print_info "All services are running."
    else
        print_error "Some services are not running!"
        systemctl status smbd nmbd avahi-daemon --no-pager
        exit 1
    fi

    # Test 2: Check mount
    print_info "Checking mount point..."
    if mountpoint -q "$MOUNT_POINT"; then
        print_info "Drive is mounted at $MOUNT_POINT"
    else
        print_error "Drive is not mounted!"
        exit 1
    fi

    # Test 3: List Samba shares
    print_info "Available Samba shares:"
    smbclient -L localhost -U "$TM_USER%" -c 2>/dev/null || true

    print_info "All tests passed!"
}

# Print summary
print_summary() {
    echo
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}              Installation completed successfully!         ${GREEN}║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${BLUE}Configuration Summary:${NC}"
    echo "  Server name:     TIMECAPSULE-PI"
    echo "  Share name:      $SHARE_NAME"
    echo "  Mount point:     $MOUNT_POINT"
    echo "  Time Machine user: $TM_USER"
    echo "  Quota:           $QUOTA_SIZE"
    echo
    echo -e "${YELLOW}Next steps on your Mac:${NC}"
    echo "  1. Open System Settings → General → Time Machine"
    echo "  2. Click 'Add Backup Disk'"
    echo "  3. Select 'TIMECAPSULE-PI' → '$SHARE_NAME'"
    echo "  4. Enter username: $TM_USER"
    echo "  5. Enter your Samba password"
    echo "  6. Start your first backup!"
    echo
    echo -e "${YELLOW}Useful commands:${NC}"
    echo "  Check Samba:     systemctl status smbd nmbd"
    echo "  Check Avahi:     systemctl status avahi-daemon"
    echo "  Check mount:     df -h | grep timecapsule"
    echo "  List shares:     smbclient -L localhost -U $TM_USER"
    echo "  Test config:     testparm"
    echo
    echo -e "${GREEN}For more information, see README.md and MANUAL_INSTALL.md${NC}"
    echo
}

# Main installation flow
main() {
    print_header

    check_root
    check_system
    detect_usb_drives
    install_packages
    get_username
    format_drive
    setup_mount
    configure_samba
    configure_avahi
    run_tests
    print_summary
}

# Run main function
main
