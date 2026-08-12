PACKAGECONFIG:remove = "gnutls"
PACKAGECONFIG:append = " openssl"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://defconfig"
SRC_URI += "file://openssl_no_md4_2.10.patch"
SRC_URI += "file://fix_HS20_build_with_INTERWORKING.patch"
SRC_URI += "file://increase_wpa_ctrl_return_buffer.patch"
SRC_URI += "file://suppress_no_eap_session_id_log.patch"
SRC_URI += "file://roaming_threshold.patch"
SRC_URI += "file://sae-key_mgmt-capability-from-driver-flag.patch"

inherit syslog-ng-config-gen logrotate_config
#inherit breakpad-logmapper
SYSLOG-NG_FILTER = "wpa_supplicant"
SYSLOG-NG_SERVICE_wpa_supplicant = "wpa_supplicant.service"
SYSLOG-NG_DESTINATION_wpa_supplicant = "wpa_supplicant.log"
SYSLOG-NG_LOGRATE_wpa_supplicant = "high"

LOGROTATE_NAME="wpa_supplicant"
LOGROTATE_LOGNAME_wpa_supplicant="wpa_supplicant.log"
#HDD_ENABLE
LOGROTATE_SIZE_wpa_supplicant="1572864"
LOGROTATE_ROTATION_wpa_supplicant="3"
#HDD_DISABLE
LOGROTATE_SIZE_MEM_wpa_supplicant="1572864"
LOGROTATE_ROTATION_MEM_wpa_supplicant="3"


do_configure:append () {
   # Add the "-fPIC" option to CFLAGS to allow the WiFi HAL module to link against wpa-supplicant
   echo "CFLAGS += -fPIC" >> wpa_supplicant/.config

   echo "CONFIG_BUILD_WPA_CLIENT_SO=y" >> wpa_supplicant/.config

   if grep -q '\bCONFIG_DEBUG_FILE\b' wpa_supplicant/.config; then
      sed -i -e '/\bCONFIG_DEBUG_FILE\b/s/.*/CONFIG_DEBUG_FILE=y/' wpa_supplicant/.config
   else
      echo "CONFIG_DEBUG_FILE=y" >> wpa_supplicant/.config
   fi

   sed -i -- 's/CONFIG_DRIVER_HOSTAP=y/\#CONFIG_DRIVER_HOSTAPAP=y/' wpa_supplicant/.config
   sed -i -- 's/#CONFIG_IEEE80211W=y/\CONFIG_IEEE80211W=y/' wpa_supplicant/.config

   #Enable the following supplicant options:
   #QCA vendor extensions to nl80211
   sed -i -- 's/#CONFIG_DRIVER_NL80211_QCA=y/\CONFIG_DRIVER_NL80211_QCA=y/' wpa_supplicant/.config
   #IEEE Std 802.11r-2008 (Fast BSS Transition)
   sed -i -- 's/#CONFIG_IEEE80211R=y/\CONFIG_IEEE80211R=y/' wpa_supplicant/.config
   #Interworking (IEEE 802.11u)
   sed -i -- 's/#CONFIG_INTERWORKING=y/\CONFIG_INTERWORKING=y/' wpa_supplicant/.config
   #Support Multi Band Operation:
   sed -i -- 's/#CONFIG_MBO=y/\CONFIG_MBO=y/' wpa_supplicant/.config

   echo "OPENSSL_NO_MD4=y" >> wpa_supplicant/.config
}

do_install:append () {
   install -d ${D}${includedir}
   install -m 0644 ${S}/src/common/wpa_ctrl.h ${D}${includedir}

   install -d ${D}${libdir}
   install -m 0644 ${S}/wpa_supplicant/libwpa_client.so ${D}${libdir}

   sed -i 's/After=.*/After=network@wlan0.service/g' ${D}/${systemd_unitdir}/system/wpa_supplicant.service
}

FILES_SOLIBSDEV = ""
FILES:${PN} += "${libdir}/libwpa_client.so"

PACKAGE_BEFORE_PN += "${PN}-extras"
FILES:${PN}-extras = "\
                        ${systemd_unitdir}/system/wpa_supplicant-nl80211@.service\
                        ${systemd_unitdir}/system/wpa_supplicant-wired@.service \
                     "

# Breakpad processname and logfile mapping
BREAKPAD_LOGMAPPER_PROCLIST = "wpa_supplicant"
BREAKPAD_LOGMAPPER_LOGLIST = "wpa_supplicant.log"
