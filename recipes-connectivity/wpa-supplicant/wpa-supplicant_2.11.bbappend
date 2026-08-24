FILESEXTRAPATHS:prepend := "${THISDIR}/files/2.11:"

# Remove 2.10-era patches added by the wildcard bbappend
SRC_URI:remove = "file://openssl_no_md4_2.10.patch"
SRC_URI:remove = "file://fix_HS20_build_with_INTERWORKING.patch"
SRC_URI:remove = "file://increase_wpa_ctrl_return_buffer.patch"
SRC_URI:remove = "file://suppress_no_eap_session_id_log.patch"
SRC_URI:remove = "file://roaming_threshold.patch"
SRC_URI:remove = "file://sae-key_mgmt-capability-from-driver-flag.patch"

SRC_URI += "file://wpa_supplicant_utc_timestamp_2.11.patch \
            file://auth_timeout_retry_logic_2.11.patch \
	    file://wpa_supp_bss_select_additional_logging_2.11.patch \
            file://auth_timeout_retry_logic_1_2.11.patch \
	    file://fix_wpa_supplicant_operating-mode_2.11.patch \
	    file://allow_wps_cancel_while_authenticating_or_associating_2.11.patch \
	    file://tkip_rc4_bug_fix_2.11.patch \
	    file://wpa_cli_command_changes_to_skip_p2p_iface_for_default_iface_2.11.patch \
            file://unii3_country_code_check_2.11.patch \
            file://openssl_no_md4_2.11.patch \
            file://fix_HS20_build_with_INTERWORKING_2.11.patch \
            file://increase_wpa_ctrl_return_buffer_2.11.patch \
            file://suppress_no_eap_session_id_log_2.11.patch \
            file://roaming_threshold_2.11.patch \
	   "
do_configure:append () {

   #Enable the following supplicant options:
   #Enable Fast Session Transfer (FST)
   sed -i -- 's/#CONFIG_FST=y/\CONFIG_FST=y/' wpa_supplicant/.config
   #Enable dbus for NetworkManager
   sed -i -- 's/#CONFIG_CTRL_IFACE_DBUS_NEW=y/\CONFIG_CTRL_IFACE_DBUS_NEW=y/' wpa_supplicant/.config
   sed -i -- 's/#CONFIG_CTRL_IFACE_DBUS=y/\CONFIG_CTRL_IFACE_DBUS=y/' wpa_supplicant/.config
   sed -i -- 's/#CONFIG_CTRL_IFACE_DBUS_INTRO=y/\CONFIG_CTRL_IFACE_DBUS_INTRO=y/' wpa_supplicant/.config
 
   #configuring SAE support in wpa_supplicant 2.11
   echo "CONFIG_SAE=y" >> wpa_supplicant/.config
}
