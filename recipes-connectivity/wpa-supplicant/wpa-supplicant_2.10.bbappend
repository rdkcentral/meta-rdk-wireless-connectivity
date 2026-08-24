FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://auth_timeout_retry_logic_2.10.patch \
	    file://wpa_supp_bss_select_additional_logging_2.10.patch \
            file://auth_timeout_retry_logic_1_2.10.patch \
	    file://fix_wpa_supplicant_operating-mode.patch \
	    file://allow_wps_cancel_while_authenticating_or_associating.patch \
	    file://tkip_rc4_bug_fix.patch \
	    file://wpa_cli_command_changes_to_skip_p2p_iface_for_default_iface.patch \
            file://unii3_country_code_check.patch \
	   "
do_configure:append () {

   #Enable the following supplicant options:
   #Enable Fast Session Transfer (FST)
   sed -i -- 's/#CONFIG_FST=y/\CONFIG_FST=y/' wpa_supplicant/.config
   #Enable dbus for NetworkManager
   sed -i -- 's/#CONFIG_CTRL_IFACE_DBUS_NEW=y/\CONFIG_CTRL_IFACE_DBUS_NEW=y/' wpa_supplicant/.config
   sed -i -- 's/#CONFIG_CTRL_IFACE_DBUS=y/\CONFIG_CTRL_IFACE_DBUS=y/' wpa_supplicant/.config
   sed -i -- 's/#CONFIG_CTRL_IFACE_DBUS_INTRO=y/\CONFIG_CTRL_IFACE_DBUS_INTRO=y/' wpa_supplicant/.config
 
}
