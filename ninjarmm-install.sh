#!/usr/bin/env bash

# Copyright (c) 2025-2026 Computer Trend
# Author: Fabian MiMe
# License: MIT
# https://github.com/c-trend/ninjaRMM2Proxmox/blob/main/LICENSE
#
# Installiert den NinjaOne-Agenten (NinjaRMM) auf Proxmox VE.
#
# Interaktiv:
#   bash -c "$(wget -qLO - https://raw.githubusercontent.com/c-trend/ninjaRMM2Proxmox/main/ninjarmm-install.sh)"
# Ohne Rückfragen (Installationslink als Argument oder in NINJA_AGENT_URL):
#   bash -c "$(wget -qLO - .../ninjarmm-install.sh)" _ "<Installationslink>"

set -Eeuo pipefail
shopt -s inherit_errexit

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

# Ausgaben von curl/dpkg/apt landen im Log, damit sie im Fehlerfall sichtbar sind
LOG=$(mktemp /tmp/ninjarmm-install.XXXXXX.log)
WORKDIR=$(mktemp -d /tmp/ninjarmm-install.XXXXXX)
trap 'rm -rf "$WORKDIR"; [[ -s "$LOG" ]] || rm -f "$LOG"' EXIT
trap 'msg_error "Unerwarteter Fehler in Zeile ${LINENO} (Log: ${LOG})"' ERR

fail() {
  msg_error "$1"
  if [[ -s "$LOG" ]]; then
    echo -e "\n${YW}Letzte Zeilen aus ${LOG}:${CL}"
    tail -n 15 "$LOG"
  fi
  exit 1
}

confirm() {
  local yn
  while true; do
    read -rp "$1 (j/n): " yn || return 1
    case $yn in
      [Jj]*) return 0 ;;
      [Nn]*) return 1 ;;
      *) echo "Antworten mit j (ja) oder n (nein)." ;;
    esac
  done
}

preflight() {
  [[ $EUID -eq 0 ]] || fail "Bitte als root ausführen (Proxmox-Shell oder sudo)."
  command -v dpkg >/dev/null || fail "dpkg nicht gefunden – das Skript ist nur für Debian-basierte Systeme (Proxmox VE)."
  command -v curl >/dev/null || fail "curl nicht gefunden (apt-get install curl)."
  # Nicht auf einem bereits defekten Paketstand installieren, apt würde sonst mitreparieren
  [[ -z "$(dpkg --audit 2>&1)" ]] \
    || fail "Die Paketverwaltung meldet unvollständige Pakete (dpkg --audit). Zuerst beheben."

  if command -v pveversion >/dev/null; then
    msg_ok "Proxmox VE erkannt: $(pveversion | head -n1)"
  else
    msg_warn "Kein Proxmox VE erkannt (pveversion fehlt) – Installation trotzdem möglich."
  fi

  if [[ -d "$AGENT_DIR" ]] || systemctl cat "$SERVICE" &>/dev/null; then
    msg_warn "NinjaOne-Agent ist bereits installiert (${AGENT_DIR})."
    if [[ $INTERACTIVE -eq 1 ]]; then
      confirm "Trotzdem neu installieren?" || { echo "Abgebrochen."; exit 0; }
    fi
  fi
}

ask_url() {
  if command -v whiptail >/dev/null; then
    # Abbrechen in whiptail liefert Exit-Code 1 – nicht als Skriptfehler werten
    AGENT_URL=$(whiptail --title "NinjaOne-Agent" \
      --inputbox "Installationslink (.deb) aus NinjaOne einfügen:" 10 70 3>&1 1>&2 2>&3) || {
      echo "Abgebrochen."; exit 0;
    }
    header_info
  else
    read -rp "Installationslink (.deb) aus NinjaOne: " AGENT_URL || AGENT_URL=""
  fi
}

install_agent() {
  # Leerzeichen/Zeilenumbrüche vom Einfügen entfernen
  AGENT_URL="${AGENT_URL//[[:space:]]/}"
  [[ -n "$AGENT_URL" ]] || fail "Kein Installationslink eingegeben. Installation abgebrochen."
  [[ "$AGENT_URL" =~ ^https://[^\"\\]+$ ]] || fail "Der Installationslink muss mit https:// beginnen."

  local deb="$WORKDIR/ninjarmm-agent.deb"
  local host="${AGENT_URL#https://}"
  host="${host%%/*}"

  msg_info "Lade NinjaOne-Agent herunter (${host})"
  # -f: HTTP-Fehler (z. B. abgelaufener Link) als Fehler werten statt HTML zu speichern.
  # URL über stdin (-K -), damit das Token nicht in der Prozessliste steht.
  curl -fsSL --retry 3 -o "$deb" -K - <<<"url = \"${AGENT_URL}\"" >>"$LOG" 2>&1 \
    || fail "Download fehlgeschlagen. Ist der Link korrekt und noch gültig?"
  local pkg version arch sysarch
  pkg=$(dpkg-deb -f "$deb" Package 2>>"$LOG") \
    || fail "Die heruntergeladene Datei ist kein gültiges .deb-Paket (Linux-Installer für Debian/Ubuntu gewählt?)."
  version=$(dpkg-deb -f "$deb" Version)
  arch=$(dpkg-deb -f "$deb" Architecture)
  sysarch=$(dpkg --print-architecture)
  msg_ok "Download abgeschlossen: ${pkg} ${version} (${arch})"

  [[ "$arch" == "$sysarch" || "$arch" == "all" ]] \
    || fail "Paket ist für ${arch}, dieses System ist ${sysarch}."
  if [[ ! "${pkg,,}" =~ ninja ]]; then
    msg_warn "Das Paket «${pkg}» sieht nicht nach dem NinjaOne-Agenten aus (Quelle: ${host})."
    [[ $INTERACTIVE -eq 1 ]] && confirm "Trotzdem installieren?" || fail "Installation abgebrochen."
  fi

  msg_info "Installiere NinjaOne-Agent"
  # apt löst Abhängigkeiten gezielt für dieses Paket auf; --no-remove verhindert,
  # dass auf dem PVE-Host dafür andere Pakete entfernt werden.
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-remove --reinstall "$deb" >>"$LOG" 2>&1 \
    || fail "Installation fehlgeschlagen."
  [[ "$(dpkg-query -W -f='${db:Status-Abbrev}' "$pkg" 2>/dev/null)" == "ii " ]] \
    || fail "Installation fehlgeschlagen: Paket ${pkg} ist nicht vollständig installiert."
  msg_ok "Installation abgeschlossen"

  msg_info "Prüfe Dienst ${SERVICE}"
  local i
  for i in {1..30}; do
    systemctl is-active --quiet "$SERVICE" && break
    sleep 1
  done
  if ! systemctl is-active --quiet "$SERVICE"; then
    {
      systemctl status "$SERVICE" --no-pager
      journalctl -u "$SERVICE" -n 20 --no-pager
    } >>"$LOG" 2>&1 || true
    fail "Paket installiert, aber der Dienst ${SERVICE} läuft nicht."
  fi
  msg_ok "Dienst ${SERVICE} läuft"

  echo -e "\n${GN}Fertig.${CL} Das Gerät erscheint nach kurzer Zeit in NinjaOne (Organisation/Standort gemäss Installationslink)."
  rm -f "$LOG"
}

AGENT_URL="${1:-${NINJA_AGENT_URL:-}}"
INTERACTIVE=1
[[ -n "$AGENT_URL" ]] && INTERACTIVE=0

header_info
echo -e "\nDieses Skript installiert den NinjaOne-Agenten auf dem Proxmox-Server.\n"
preflight

if [[ $INTERACTIVE -eq 1 ]]; then
  confirm "Fortfahren?" || { exit 0; }
  ask_url
fi

install_agent
