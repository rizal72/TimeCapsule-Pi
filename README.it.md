# TimeCapsuleRPi - Time Machine su Raspberry Pi 4

## 🎯 Obiettivo

Configurare la **Raspberry Pi 4** come server **Time Machine** completo per backup di rete, usando un disco USB esterno.

## Perché Raspberry Pi 4?

| Vantaggio | Dettaglio |
|-----------|-----------|
| ✅ **Sempre accesa** | Già attiva 24/7 per PaperGate |
| ✅ **Controllo completo** | Scegliamo cosa installare (no limitazioni vendor) |
| ✅ **Samba 4.x completo** | Supporto vfs_fruit per Time Machine |
| ✅ **mDNS/Bonjour** | Avahi già installato |
| ✅ **USB 3.0** | Velocità ottima per disco esterno |
| ✅ **Tailscale** | Accessibile anche da remoto |
| ✅ **Economico** | Hardware che hai già |

## Stato Pi4 - Analisi Completata

### Hardware
- **Modello**: Raspberry Pi 4
- **CPU**: ARMv8 (aarch64)
- **RAM**: 3.7 GB
- **OS**: Raspberry Pi OS Bullseye (Debian 11)
- **Kernel**: 6.1.21-v8+
- **Spazio SD**: 58GB (13GB usati, 43GB liberi)
- **USB**: Hub 3.0 + Hub 2.0 presenti

### Software Già Installato
- ✅ **Avahi 0.8** - mDNS/Bonjour daemon (attivo)
- ✅ **libsmbclient** - Librerie Samba client
- ✅ **Tailscale** - VPN già configurata
- ✅ **PaperGate** - Gateway attivo

### Software Da Installare
- ❌ **Samba server** - NON installato (disponibile: 4.13.13)
- ⚠️ **Configurare Time Machine share** con vfs_fruit

---

## 📋 Stato del Progetto

### ✅ Fase 1: Analisi Pi4 - COMPLETATA
- [x] Verificato sistema operativo (Raspberry Pi OS Bullseye)
- [x] Verificato Avahi installato e attivo
- [x] Verificato spazio su SD (43GB liberi)
- [x] Verificate porte USB (3.0 + 2.0)
- [x] Identificata versione Samba disponibile (4.13.13)

### ✅ Fase 2: Installazione Software - COMPLETATA
- [x] Installare Samba 4.13.13
- [x] Verificare configurazione Avahi
- [x] Creare utente per Time Machine

### ✅ Fase 3: Configurazione Disco - COMPLETATA
- [x] Collegare HD "Cerasuolo" alla Pi4 (rinominato in "timecapsule")
- [x] Formattare in ext4
- [x] Configurare mount automatico in fstab
- [x] Creare mount point /mnt/timecapsule

### ✅ Fase 4: Configurazione Samba - COMPLETATA
- [x] Creare smb.conf per Time Machine
- [x] Abilitare vfs_fruit
- [x] Configurare autenticazione (utente: timemachine, password: timecapsule)
- [x] Creare servizio Avahi per discovery automatica

### ⏳ Fase 5: Test Time Machine - IN CORSO
- [ ] Verificare visibilità su macOS
- [ ] Configurare Time Machine sul Mac
- [ ] Testare backup iniziale

---

## 🔧 Configurazione Pi4

### Accesso
```bash
# Via Tailscale (consigliato)
ssh pi@pi4

# Via rete locale
ssh pi@192.168.1.12  # o l'IP locale della Pi4
```

### Mount locale MacFUSE (se necessario)
```bash
# Per accedere ai file dalla rete locale
mkdir -p ~/pi4
sshfs pi@pi4: ~/pi4
```

### Comandi Utili
```bash
# Verifica stato Avahi
systemctl status avahi-daemon

# Verifica porte USB
lsusb

# Verifica dischi collegati
lsblk
ls /dev/sd*

# Verifica spazio disco
df -h
```

---

## 📦 Installazione Samba

```bash
# Aggiorna repository
sudo apt update

# Installa Samba
sudo apt install samba

# Verifica installazione
smbd --version
systemctl status smbd nmbd
```

---

## 📝 Configurazione Samba per Time Machine

File: `/etc/samba/smb.conf`

```ini
[global]
    server string = Raspberry Pi Time Machine
    workgroup = WORKGROUP
    log file = /var/log/samba/log.%m
    max log size = 1000
    log level = 2
    pid directory = /var/run/samba
    lock directory = /var/run/samba

    # Protocollo SMB2/3
    min protocol = SMB2
    max protocol = SMB3

    # Time Machine
    fruit:time machine = yes
    fruit:delete vacuum files = yes
    fruit:veto apple double = no
    fruit:metadata = stream
    fruit:encoding = native
    fruit:copyfile = yes

    # VFS modules
    vfs objects = catia fruit streams_xattr

    # Autenticazione
    security = user
    passdb backend = tdbsam

# Share Time Machine
[TimeMachine]
    comment = Time Machine Backup
    path = /mnt/timemachine
    browseable = yes
    read only = no
    create mask = 0666
    directory mask = 0777
    guest ok = no
    valid users = timemachine

    # Time Machine specific
    fruit:time machine max size = 2T
    vfs objects = catia fruit streams_xattr
```

---

## 📚 Risorse

- [Samba Time Machine Configuration](https://www.samba.org/samba/docs/current/man-html/smb.conf.5.html)
- [Raspberry Pi Time Machine Tutorial](https://www.jwtey.com/raspberry-pi-time-machine/)
- [Avahi mDNS Configuration](https://www.avahi.org/)

---

## Log

- **2026-02-01 21:00**: Progetto inizializzato
- **2026-02-01 21:30**: Analisi Pi4 completata
  - OS: Raspberry Pi OS Bullseye
  - Avahi: installato e attivo
  - Samba: DA installare (v4.13.13 disponibile)
  - Spazio: 43GB liberi su SD
- **2026-02-01 21:00**: Fase 2-4 COMPLETATE
  - Samba 4.13.13 installato e configurato
  - HD "Cerasuolo" formattato in ext4, montato su /mnt/timecapsule
  - Utente Samba creato: timemachine / timecapsule
  - Servizio Avahi configurato per discovery automatica
  - Share TimeMachine funzionante (testato in locale)
- **2026-02-01 21:30**: Pronto per test da macOS

---

**Autore**: Riccardo Sallusti
**Data inizio**: 1 Febbraio 2026
**Stato**: Configurazione completata, in attesa di test macOS
