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

# Paket über den Installationspfad ermitteln statt den Namen fest anzunehmen.
# dpkg-query: Exit 1 = kein Paket besitzt den Pfad, Exit 2 = Datenbankfehler.
rc=0
OWNERS=$(LC_ALL=C dpkg-query -S "$AGENT_DIR" 2>/dev/null) || rc=$?
if [[ $rc -gt 1 ]]; then
  msg_error "Abfrage der Paketdatenbank fehlgeschlagen (dpkg-query -S, Exit ${rc}). Abbruch ohne Änderungen."
  exit 1
fi
# Format «paket[:arch][, paket2]: pfad»; Diversion-Zeilen überspringen
mapfile -t PACKAGES < <(printf '%s\n' "$OWNERS" | grep -v '^diversion ' | sed 's/: .*//' | tr ',' '\n' | sed 's/^ *//;/^$/d' | sort -u)
if [[ ${#PACKAGES[@]} -gt 1 ]]; then
  msg_error "Mehrere Pakete besitzen ${AGENT_DIR}: ${PACKAGES[*]} – bitte manuell prüfen (dpkg -l | grep -i ninja)."
  exit 1
fi

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

if [[ ${#PACKAGES[@]} -eq 1 ]]; then
  PKG="${PACKAGES[0]}"
  msg_info "Entferne Paket ${PKG}"
  LOG=$(mktemp /tmp/ninjarmm-uninstall.XXXXXX.log)
  if ! dpkg --purge "$PKG" >"$LOG" 2>&1; then
    # Keine Dateien von Hand löschen, solange dpkg das Paket noch führt
    msg_error "dpkg --purge ${PKG} fehlgeschlagen. Ausgabe: ${LOG}"
    tail -n 15 "$LOG"
    exit 1
  fi
  rm -f "$LOG"
  msg_ok "Paket ${PKG} entfernt"
fi

# Reste entfernen (von Maintainer-Skripten erzeugte Dateien oder Installation ohne Paket)
msg_info "Räume Reste auf"
rm -rf "$AGENT_DIR" \
  && rm -f "/etc/systemd/system/${SERVICE}" \
           "/etc/systemd/system/multi-user.target.wants/${SERVICE}" \
           "/lib/systemd/system/${SERVICE}" \
  || { msg_error "Reste konnten nicht entfernt werden."; exit 1; }
systemctl daemon-reload || { msg_error "systemctl daemon-reload fehlgeschlagen."; exit 1; }
systemctl reset-failed "$SERVICE" &>/dev/null || true
msg_ok "Reste entfernt"

if [[ -d "$AGENT_DIR" ]] || systemctl cat "$SERVICE" &>/dev/null \
   || [[ -n "${PKG:-}" && "$(dpkg-query -W -f='${db:Status-Abbrev}' "$PKG" 2>/dev/null)" == i* ]]; then
  msg_error "Agent konnte nicht vollständig entfernt werden."
  exit 1
fi

msg_ok "NinjaOne-Agent wurde deinstalliert."
echo -e "\n${YW}Hinweis:${CL} Das Gerät in NinjaOne zusätzlich löschen, sonst bleibt es als offline sichtbar."
