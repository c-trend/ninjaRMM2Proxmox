# NinjaOne-Agent (NinjaRMM) auf Proxmox VE

Interaktive Skripte, um den NinjaOne-Agenten auf einem Proxmox-VE-Host zu
installieren bzw. wieder zu entfernen. Proxmox VE basiert auf Debian, der
Agent wird daher über das `.deb`-Paket aus NinjaOne installiert.

## Voraussetzungen

- Proxmox VE (oder ein anderes Debian-basiertes System), Shell als `root`
- `curl` und `wget` (auf Proxmox standardmässig vorhanden)
- Ausgehender HTTPS-Zugriff auf GitHub und die NinjaOne-Instanz
- Installationslink für den **Linux-Agenten (Debian/Ubuntu, `.deb`)** aus
  NinjaOne – er bestimmt Organisation und Standort, in die das Gerät kommt

## Installation

In der Proxmox-Shell (Web-UI → Knoten → Shell oder per SSH) ausführen:

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/c-trend/ninjaRMM2Proxmox/main/ninjarmm-install.sh)"
```

Das Skript

1. prüft root-Rechte, Debian/Proxmox und eine allfällige bestehende Installation,
2. fragt nach dem Installationslink,
3. lädt das Paket herunter und prüft, ob es ein gültiges `.deb` ist,
4. installiert es (fehlende Abhängigkeiten via `apt-get install -f`),
5. prüft, ob der Dienst `ninjarmm-agent.service` läuft.

Bei Fehlern bleibt ein Log unter `/tmp/ninjarmm-install.*.log` liegen, die
letzten Zeilen werden direkt angezeigt.

### Ohne Rückfragen (z. B. für mehrere Hosts)

Den Installationslink als Argument oder in `NINJA_AGENT_URL` übergeben:

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/c-trend/ninjaRMM2Proxmox/main/ninjarmm-install.sh)" _ "<Installationslink>"
```

Achtung: Der Link enthält das Token der Organisation – nicht in Tickets,
Chats oder öffentliche Doku kopieren.

## Deinstallation

```bash
bash -c "$(wget -qLO - https://raw.githubusercontent.com/c-trend/ninjaRMM2Proxmox/main/ninjarmm-uninstall.sh)"
```

Ohne Rückfrage: `... _ -y` anhängen.

Das Skript stoppt den Dienst, entfernt das Paket sauber über `dpkg --purge`
(Paketname wird über `/opt/NinjaRMMAgent` ermittelt) und räumt Reste
(Programmordner, systemd-Units) auf. Das Gerät danach zusätzlich in
NinjaOne löschen, sonst bleibt es dort als offline stehen.

## Kontrolle

```bash
systemctl status ninjarmm-agent.service
ls /opt/NinjaRMMAgent/programfiles
dpkg -l | grep -i ninja
```

## Sicherheit

Die Einzeiler führen ein Skript direkt aus dem Internet aus. Wer das nicht
möchte, lädt die Datei zuerst herunter, prüft sie und startet sie lokal:

```bash
wget https://raw.githubusercontent.com/c-trend/ninjaRMM2Proxmox/main/ninjarmm-install.sh
less ninjarmm-install.sh
bash ninjarmm-install.sh
```

## Änderungen

- **2026-10** – Repo nach `c-trend` verschoben, Links angepasst.
  Installation: root-/Systemprüfung, Erkennung bestehender Installation,
  Download mit HTTP-Fehlerprüfung und `.deb`-Validierung, Abbrechen im
  Eingabedialog sauber behandelt, Dienstprüfung nach der Installation,
  Fehlerlog, Modus ohne Rückfragen. Deinstallation: Paket über
  `dpkg --purge` statt Löschen von Dateien in `/var/lib/dpkg/info`
  (beschädigte die Paketdatenbank), Modus `-y`, Erfolgskontrolle.
  Doppeltes `beta-uninstall2.sh` entfernt, `.gitattributes` erzwingt LF.
- **2025-01** – Erste Version.

## Lizenz

MIT, siehe [LICENSE](LICENSE).
