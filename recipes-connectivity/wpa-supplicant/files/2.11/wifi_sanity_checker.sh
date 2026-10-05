#!/usr/bin/env bash
#
# wifi_sanity_checker.sh
#
# Wi-Fi connection test harness for a Linux client running wpa_supplicant.
#
# Given an SSID / username / password / security mode, this script:
#   1. Creates a wpa_supplicant config file in /tmp for the requested network,
#      unless the config file already exists, in which case it is used as-is.
#   2. Stops any running wpa_supplicant instance on the interface and
#      restarts it in the background (-B) with verbose debug logging
#      redirected to a log file.
#   3. Polls `wpa_cli status` until the link reaches COMPLETED or a
#      timeout/hard-failure is detected.
#   4. On failure, scans the wpa_supplicant debug log for well-known
#      failure signatures (EAPOL/EAP timeouts, wrong PSK, cert errors,
#      association rejects, ctrl-interface init failures, etc.) and prints
#      a human-readable diagnosis.
#   5. On success, prints connection details (BSSID, frequency, key_mgmt,
#      pairwise/group cipher...).
#
# Must be run as root (interface control + wpa_supplicant control socket).
#
# Usage:
#   sudo ./test_wifi_wpa.sh --ssid MySSID --security wpa-psk --password 'secret' [options]
#
# Run --help for the full option list.

set -uo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
IFACE="wlan0"
DRIVER="nl80211"
SECURITY=""
SSID=""
USERNAME=""
PASSWORD=""
ANON_IDENTITY=""
CA_CERT=""
PHASE2_OVERRIDE=""
TIMEOUT=30
CONF=""
LOGFILE="/tmp/wpa_supplicant_test.txt"
CTRL_IFACE_DIR="/var/run/wpa_supplicant"
KEEP_RUNNING=0

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
    C_RED=$'\e[31m'; C_GRN=$'\e[32m'; C_YEL=$'\e[33m'; C_CYN=$'\e[36m'; C_BLD=$'\e[1m'; C_OFF=$'\e[0m'
else
    C_RED=""; C_GRN=""; C_YEL=""; C_CYN=""; C_BLD=""; C_OFF=""
fi
info()  { printf '%s[INFO]%s  %s\n'  "$C_CYN" "$C_OFF" "$*"; }
warn()  { printf '%s[WARN]%s  %s\n'  "$C_YEL" "$C_OFF" "$*"; }
err()   { printf '%s[ERROR]%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; }
ok()    { printf '%s[ OK ]%s  %s\n'  "$C_GRN" "$C_OFF" "$*"; }
hr()    { printf '%s\n' "--------------------------------------------------------------------"; }

usage() {
    cat <<EOF
Usage: sudo $0 --ssid <SSID> --security <mode> [options]

Required:
  -s, --ssid <name>          SSID of the network to test
  -m, --security <mode>      One of: open, wpa-psk, sae, wpa-eap-peap, wpa-eap-ttls

Credentials (required depending on --security):
  -p, --password <pass>      PSK passphrase (wpa-psk/sae) or EAP password (eap-*)
  -u, --username <user>      EAP identity (required for wpa-eap-peap / wpa-eap-ttls)
      --anon-identity <id>   Optional EAP anonymous identity (outer identity)
      --ca-cert <path>       Optional CA certificate for EAP server validation
      --phase2 <str>         Override phase2 string (default: auth=MSCHAPV2)

Interface / behaviour:
  -i, --iface <name>         Wireless interface (default: wlan0)
  -D, --driver <name>        wpa_supplicant driver (default: nl80211)
  -c, --conf <path>          wpa_supplicant config file to use/create
                              (default: /tmp/wpa_supplicant_test-<iface>.conf)
                              If this file already exists, it is used as-is
                              and not regenerated.
  -t, --timeout <seconds>    Max seconds to wait for association (default: 30)
      --log-file <path>      Verbose wpa_supplicant log path (default: /tmp/wpa_supplicant_test.txt)
      --keep-running         Do not kill wpa_supplicant after the test finishes
  -h, --help                 Show this help

Examples:
  sudo $0 -s HomeWifi -m wpa-psk -p 'MyPassphrase'
  sudo $0 -s CorpWifi -m wpa-eap-peap -u alice -p 'MyPassword'
  sudo $0 -s Wifi6 -m sae -p 'MyPassphrase' -i wlan1
EOF
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--ssid) SSID="$2"; shift 2 ;;
        -m|--security) SECURITY="$2"; shift 2 ;;
        -p|--password) PASSWORD="$2"; shift 2 ;;
        -u|--username) USERNAME="$2"; shift 2 ;;
        --anon-identity) ANON_IDENTITY="$2"; shift 2 ;;
        --ca-cert) CA_CERT="$2"; shift 2 ;;
        --phase2) PHASE2_OVERRIDE="$2"; shift 2 ;;
        -i|--iface) IFACE="$2"; shift 2 ;;
        -D|--driver) DRIVER="$2"; shift 2 ;;
        -c|--conf) CONF="$2"; shift 2 ;;
        -t|--timeout) TIMEOUT="$2"; shift 2 ;;
        --log-file) LOGFILE="$2"; shift 2 ;;
        --keep-running) KEEP_RUNNING=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) err "Unknown option: $1"; usage; exit 2 ;;
    esac
done

[[ -z "$CONF" ]] && CONF="/tmp/wpa_supplicant_test-${IFACE}.conf"

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------
if [[ -z "$SSID" || -z "$SECURITY" ]]; then
    err "--ssid and --security are required"
    usage
    exit 2
fi

case "$SECURITY" in
    open) ;;
    wpa-psk|sae)
        [[ -z "$PASSWORD" ]] && { err "--password is required for security mode '$SECURITY'"; exit 2; }
        ;;
    wpa-eap-peap|wpa-eap-ttls)
        [[ -z "$USERNAME" ]] && { err "--username is required for security mode '$SECURITY'"; exit 2; }
        [[ -z "$PASSWORD" ]] && { err "--password is required for security mode '$SECURITY'"; exit 2; }
        ;;
    *)
        err "Unknown security mode '$SECURITY'. Use one of: open, wpa-psk, sae, wpa-eap-peap, wpa-eap-ttls"
        exit 2
        ;;
esac

if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root (needed to control $IFACE and wpa_supplicant)."
    exit 3
fi

if ! ip link show "$IFACE" >/dev/null 2>&1; then
    err "Interface '$IFACE' does not exist. Available wireless interfaces:"
    ip -o link show | awk -F': ' '{print "  - "$2}'
    exit 3
fi

# ---------------------------------------------------------------------------
# Build the network{} block for the requested security mode
# ---------------------------------------------------------------------------
build_network_block() {
    local esc_ssid esc_pass esc_user esc_anon phase2
    esc_ssid=$(printf '%s' "$SSID" | sed 's/"/\\"/g')

    case "$SECURITY" in
        open)
            cat <<NET
network={
    ssid="${esc_ssid}"
    key_mgmt=NONE
}
NET
            ;;
        wpa-psk)
            esc_pass=$(printf '%s' "$PASSWORD" | sed 's/"/\\"/g')
            cat <<NET
network={
    ssid="${esc_ssid}"
    key_mgmt=WPA-PSK
    psk="${esc_pass}"
}
NET
            ;;
        sae)
            esc_pass=$(printf '%s' "$PASSWORD" | sed 's/"/\\"/g')
            cat <<NET
network={
    ssid="${esc_ssid}"
    key_mgmt=SAE
    ieee80211w=2
    psk="${esc_pass}"
}
NET
            ;;
        wpa-eap-peap|wpa-eap-ttls)
            esc_user=$(printf '%s' "$USERNAME" | sed 's/"/\\"/g')
            esc_pass=$(printf '%s' "$PASSWORD" | sed 's/"/\\"/g')
            esc_anon=$(printf '%s' "${ANON_IDENTITY:-$USERNAME}" | sed 's/"/\\"/g')
            phase2="${PHASE2_OVERRIDE:-auth=MSCHAPV2}"
            [[ "$SECURITY" == "wpa-eap-ttls" && -z "$PHASE2_OVERRIDE" ]] && phase2="autheap=MSCHAPV2"
            {
                echo "network={"
                echo "    ssid=\"${esc_ssid}\""
                echo "    key_mgmt=WPA-EAP"
                [[ "$SECURITY" == "wpa-eap-peap" ]] && echo "    eap=PEAP"
                [[ "$SECURITY" == "wpa-eap-ttls" ]] && echo "    eap=TTLS"
                echo "    identity=\"${esc_user}\""
                echo "    anonymous_identity=\"${esc_anon}\""
                echo "    password=\"${esc_pass}\""
                echo "    phase2=\"${phase2}\""
                [[ -n "$CA_CERT" ]] && echo "    ca_cert=\"${CA_CERT}\""
                echo "}"
            }
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Write the wpa_supplicant config only if it doesn't already exist
# ---------------------------------------------------------------------------
write_conf() {
    if [[ -f "$CONF" ]]; then
        ok "Config file already exists, using as-is: $CONF"
        return
    fi

    mkdir -p "$(dirname "$CONF")"
    {
        echo "ctrl_interface=DIR=${CTRL_IFACE_DIR}"
        echo "update_config=1"
        echo "country=00"
        echo
        build_network_block
    } > "$CONF"

    chmod 600 "$CONF"
    ok "Created config file: $CONF"
}

# ---------------------------------------------------------------------------
# Restart wpa_supplicant on the interface with verbose logging
# ---------------------------------------------------------------------------
restart_supplicant() {
    info "Stopping any existing wpa_supplicant on $IFACE ..."
    wpa_cli -i "$IFACE" terminate >/dev/null 2>&1
    local old_pids
    old_pids=$(pgrep -f "wpa_supplicant.*-i ${IFACE}([^0-9]|$)" 2>/dev/null)
    [[ -n "$old_pids" ]] && kill -15 $old_pids 2>/dev/null
    sleep 1

    rm -f "$LOGFILE"
    : > "$LOGFILE"

    ip link set "$IFACE" up 2>/dev/null
    if command -v rfkill >/dev/null 2>&1; then
        rfkill unblock wifi 2>/dev/null
    fi

    info "Starting wpa_supplicant on $IFACE (driver=$DRIVER), config=$CONF, logging to $LOGFILE ..."
    wpa_supplicant -B -i "$IFACE" -c "$CONF" -D"$DRIVER" -f "$LOGFILE" -dd
    local rc=$?
    if [[ $rc -ne 0 ]]; then
        err "wpa_supplicant failed to start (exit code $rc). Check $LOGFILE for details."
        exit 4
    fi
    ok "wpa_supplicant launched in the background; waiting for association ..."
}

# ---------------------------------------------------------------------------
# Poll wpa_cli status until COMPLETED or timeout
# ---------------------------------------------------------------------------
FINAL_STATE=""
poll_status() {
    local waited=0
    local state=""
    info "Waiting up to ${TIMEOUT}s for association (interface=$IFACE) ..."
    while (( waited < TIMEOUT )); do
        state=$(wpa_cli -i "$IFACE" status 2>/dev/null | awk -F= '/^wpa_state=/{print $2}')
        [[ -z "$state" ]] && state="UNKNOWN"
        printf '\r  t=%-3ds  wpa_state=%-20s' "$waited" "$state"

        if [[ "$state" == "COMPLETED" ]]; then
            echo
            FINAL_STATE="COMPLETED"
            return 0
        fi

        # Bail out early on repeated hard failures visible in the log
        if grep -qE 'CTRL-EVENT-EAP-FAILURE|CTRL-EVENT-SSID-TEMP-DISABLED|4-Way Handshake failed|Failed to initialize control interface|Failed to add interface' "$LOGFILE" 2>/dev/null; then
            echo
            FINAL_STATE="$state"
            return 1
        fi

        sleep 1
        ((waited++))
    done
    echo
    FINAL_STATE="$state"
    return 1
}

# ---------------------------------------------------------------------------
# Analyse the debug log for known failure signatures
# ---------------------------------------------------------------------------
analyze_log() {
    local -a patterns messages
    patterns=(
        'CTRL-EVENT-EAP-FAILURE|EAP authentication completed unsuccessfully'
        'TLS: Certificate verification failed|Certificate chain length'
        'pre-shared key may be incorrect|WRONG_KEY'
        'CTRL-EVENT-SSID-TEMP-DISABLED'
        'CTRL-EVENT-ASSOC-REJECT'
        'Association request to the driver failed'
        'No suitable network found'
        'EAPOL:.*[Tt]imeout|EAP: Failed to get type|EAPOL-EAP-TIMEOUT'
        'WPA: Failed to parse WPA IE'
        'Authentication with .* timed out'
        'deauthenticating by local choice|CTRL-EVENT-DISCONNECTED'
        'Trying to associate with|SME: Trying to authenticate'
        'Failed to initialize control interface|Failed to add interface'
    )
    messages=(
        "EAP authentication failed - verify username/password and EAP method (PEAP/TTLS)"
        "Server certificate validation failed - check ca_cert / server certificate trust"
        "4-Way Handshake failed - the PSK/passphrase is most likely incorrect"
        "Network temporarily disabled after repeated authentication failures"
        "Association was rejected by the AP - check status_code in the log below"
        "Driver/interface failed to send the association request - check interface/driver state"
        "SSID not found - check SSID spelling/case, or AP may be out of range"
        "EAPOL/EAP negotiation timed out - no response from authenticator/RADIUS server"
        "Security/IE mismatch - selected security mode likely does not match the AP configuration"
        "802.11 authentication timed out - AP may be out of range or blocking the client (MAC filter?)"
        "Client got disconnected during the attempt - see CTRL-EVENT-DISCONNECTED reason code below"
        "Association attempt was seen in the log but never completed"
        "wpa_supplicant could not initialize its control interface/socket (check ctrl_interface config, permissions, or a stale process holding the socket)"
    )

    local found=0
    hr
    echo "${C_BLD}Log diagnosis (from $LOGFILE)${C_OFF}"
    hr
    for i in "${!patterns[@]}"; do
        if grep -qE "${patterns[$i]}" "$LOGFILE" 2>/dev/null; then
            found=1
            warn "${messages[$i]}"
            grep -E "${patterns[$i]}" "$LOGFILE" | tail -n 3 | sed 's/^/      | /'
        fi
    done

    if [[ $found -eq 0 ]]; then
        warn "No known failure signature matched. Showing the last 30 log lines for manual review:"
        tail -n 30 "$LOGFILE" 2>/dev/null | sed 's/^/      | /'
    fi
}

# ---------------------------------------------------------------------------
# Print final success details
# ---------------------------------------------------------------------------
print_success() {
    local status
    status=$(wpa_cli -i "$IFACE" status 2>/dev/null)
    hr
    ok "${C_BLD}CONNECTED${C_OFF} - $IFACE associated to '$SSID'"
    hr
    echo "$status" | grep -E '^(ssid|bssid|freq|key_mgmt|pairwise_cipher|group_cipher|wifi_generation|ip_address|address)=' \
        | sed 's/^/  /'
    hr
}

# ---------------------------------------------------------------------------
# Cleanup on exit
# ---------------------------------------------------------------------------
cleanup() {
    if [[ $KEEP_RUNNING -eq 0 ]]; then
        info "Stopping wpa_supplicant on $IFACE ..."
        wpa_cli -i "$IFACE" terminate >/dev/null 2>&1
        local pids
        pids=$(pgrep -f "wpa_supplicant.*-i ${IFACE}([^0-9]|$)" 2>/dev/null)
        [[ -n "$pids" ]] && kill -15 $pids 2>/dev/null
    else
        info "--keep-running set: leaving wpa_supplicant running on $IFACE"
    fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
hr
echo "${C_BLD}Wi-Fi test: iface=$IFACE ssid=$SSID security=$SECURITY${C_OFF}"
hr

write_conf
restart_supplicant

if poll_status; then
    print_success
    echo
    ok "Full verbose log available at: $LOGFILE"
    exit 0
else
    hr
    err "${C_BLD}NOT CONNECTED${C_OFF} - final wpa_state=$FINAL_STATE (timeout=${TIMEOUT}s)"
    analyze_log
    echo
    err "Full verbose log available at: $LOGFILE"
    exit 1
fi
