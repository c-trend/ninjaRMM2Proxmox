#!/usr/bin/env bash

# Copyright (c) 2025-2026 Computer Trend
# Author: Fabian MiMe
# License: MIT
# https://github.com/c-trend/ninjaRMM2Proxmox/blob/main/LICENSE
#
# Entfernt den NinjaOne-Agenten (NinjaRMM) von Proxmox VE.
#
# Interaktiv:
#   bash -c "$(wget -qLO - https://raw.githubusercontent.com/c-trend/ninjaRMM2Proxmox/main/ninjarmm-uninstall.sh)"
# Ohne Rückfrage:
#   bash -c "$(wget -qLO - .../ninjarmm-uninstall.sh)" _ -y

set -Euo pipefail

SERVICE="ninjarmm-agent.service"
AGENT_DIR="/opt/NinjaRMMAgent"

RD=$'\033[01;31m'
YW=$'\033[33m'
GN=$'\033[1;92m'
CL=$'\033[m'
BFR=$'\r\033[K'
HOLD="-"
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"
WARN="${YW}!${CL}"

header_info() {
  clear 2>/dev/null || true
  cat <<"EOF"
   _____                            _              _______                 _
  / ____|                          | |            |__   __|               | |
 | |     ___  _ __ ___  _ __  _   _| |_ ___ _ __     | |_ __ ___ _ __   __| |
 | |    / _ \| '_ ` _ \| '_ \| | | | __/ _ \ '__|    | | '__/ _ \ '_ \ / _` |
 | |___| (_) | | | | | | |_) | |_| | ||  __/ |       | | | |  __/ | | | (_| |
  \_____\___/|_| |_| |_| .__/ \__,_|\__\___|_|       |_|_|  \___|_| |_|\__,_|
                       | |
                       |_|
EOF
}

msg_info()  { echo -ne " ${HOLD} ${YW}$1...${CL}"; }
msg_ok()    { echo -e "${BFR} ${CM} ${GN}$1${CL}"; }
msg_warn()  { echo -e "${BFR} ${WARN} ${YW}$1${CL}"; }
msg_error() { echo -e "${BFR} ${CROSS} ${RD}$1${CL}"; }

header_info

if [[ $EUID -ne 0 ]]; then
  msg_error "Bitte als root ausführen (Proxmox-Shell oder sudo)."
  exit 1
fi

# Paket über den Installationspfad ermitteln statt den Namen fest anzunehmen
mapfile -t PACKAGES < <(dpkg -S "$AGENT_DIR" 2>/dev/null | cut -d: -f1 | tr ',' '\n' | sed 's/^ *//' | sort -u)

if [[ ${#PACKAGES[@]} -eq 0 && ! -d "$AGENT_DIR" ]] && ! systemctl cat "$SERVICE" &>/dev/null; then
  msg_ok "Kein NinjaOne-Agent gefunden – nichts zu tun."
  exit 0
fi

if [[ "${1:-}" != "-y" ]]; then
  read -rp "Möchten Sie den NinjaOne-Agenten wirklich deinstallieren? (j/n): " choice || choice=""
  case "$choice" in
    [Jj]*) ;;
    *) echo "Deinstallation abgebrochen."; exit 0 ;;
  esac
fi

msg_info "Stoppe Dienst ${SERVICE}"
systemctl disable --now "$SERVICE" &>/dev/null || true
msg_ok "Dienst gestoppt"

PURGED=0
if [[ ${#PACKAGES[@]} -gt 0 ]]; then
  msg_info "Entferne Paket ${PACKAGES[*]}"
  if dpkg --purge "${PACKAGES[@]}" &>/dev/null; then
    PURGED=1
    msg_ok "Paket ${PACKAGES[*]} entfernt"
  else
    msg_warn "dpkg --purge fehlgeschlagen – räume Dateien manuell auf"
  fi
fi

# Reste entfernen (auch wenn der Agent ohne Paketverwaltung installiert wurde)
rm -rf "$AGENT_DIR"
rm -f "/etc/systemd/system/${SERVICE}" \
      "/etc/systemd/system/multi-user.target.wants/${SERVICE}" \
      "/lib/systemd/system/${SERVICE}"
systemctl daemon-reload
systemctl reset-failed &>/dev/null || true

if [[ -d "$AGENT_DIR" ]] || systemctl is-active --quiet "$SERVICE"; then
  msg_error "Agent konnte nicht vollständig entfernt werden."
  exit 1
fi

msg_ok "NinjaOne-Agent wurde deinstalliert."
if [[ ${#PACKAGES[@]} -gt 0 && $PURGED -eq 0 ]]; then
  msg_warn "Paketeintrag ${PACKAGES[*]} steht noch in dpkg – prüfen mit: dpkg -l | grep -i ninja"
fi
echo -e "\n${YW}Hinweis:${CL} Das Gerät in NinjaOne zusätzlich löschen, sonst bleibt es als offline sichtbar."
