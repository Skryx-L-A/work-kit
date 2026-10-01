#!/usr/bin/env bash
# Reads the laptop's state. Changes nothing, needs no root.

echo "System:       $(lsb_release -ds 2>/dev/null)"
echo "Encrypted:    $(lsblk -o FSTYPE | grep -q crypto_LUKS && echo yes || echo NO)"
echo "Secure Boot:  $(mokutil --sb-state 2>/dev/null || echo unknown)"
echo "sudo:         $(id -nG | grep -qw sudo && echo yes || echo no)"
echo "Auto updates: $(systemctl is-enabled unattended-upgrades 2>/dev/null || echo no)"
echo "Lock after:   $(gsettings get org.gnome.desktop.session idle-delay 2>/dev/null | awk '{print $2/60}') min"
echo "CPU:          $(lscpu | awk -F: '/Model name/{print $2}' | xargs), $(nproc) threads"
echo "RAM:          $(free -h | awk '/Mem:/{print $2}')"
echo "Disk free:    $(df -h "$HOME" | awk 'NR==2{print $4}')"
echo "GPU:          $(lspci 2>/dev/null | grep -iE 'vga|3d' | cut -d: -f3 | xargs)"
