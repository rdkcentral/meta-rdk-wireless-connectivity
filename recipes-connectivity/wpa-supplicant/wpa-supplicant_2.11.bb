SUMMARY = "Client for Wi-Fi Protected Access (WPA)"
HOMEPAGE = "http://w1.fi/wpa_supplicant/"
BUGTRACKER = "http://w1.fi/security/"
SECTION = "network"
LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://COPYING;md5=5ebcb90236d1ad640558c3d3cd3035df \
                    file://README;beginline=1;endline=56;md5=6e4b25e7d74bfc44a32ba37bdf5210a6 \
                    file://wpa_supplicant/wpa_supplicant.c;beginline=1;endline=12;md5=f5ccd57ea91e04800edb88267bf8eae4"
DEPENDS = "dbus libnl"
RRECOMMENDS:${PN} = "wpa-supplicant-passphrase wpa-supplicant-cli"

PACKAGECONFIG ??= "gnutls"
PACKAGECONFIG[gnutls] = ",,gnutls libgcrypt"
PACKAGECONFIG[openssl] = ",,openssl"

inherit pkgconfig systemd

FILESEXTRAPATHS:prepend := "${THISDIR}/files/2.11:"

SYSTEMD_SERVICE:${PN} = "wpa_supplicant.service"
SYSTEMD_AUTO_ENABLE = "disable"

SRC_URI = "http://w1.fi/releases/wpa_supplicant-${PV}.tar.gz  \
           file://${PV}/defconfig \
           file://${PV}/wpa-supplicant.sh \
           file://${PV}/wpa_supplicant.conf \
           file://${PV}/wpa_supplicant.conf-sane \
           file://${PV}/99_wpa_supplicant \
           file://0001-macsec_linux-Hardware-offload-requires-Linux-headers.patch \
           file://0002-defconfig-Update-Opportunistic-Wireless-Encryption-O.patch \
           file://CVE-2025-24912-01.patch \
           file://CVE-2025-24912-02.patch \
          "
SRC_URI[sha256sum] = "912ea06f74e30a8e36fbb68064d6cdff218d8d591db0fc5d75dee6c81ac7fc0a"

CVE_PRODUCT = "wpa_supplicant"

S = "${WORKDIR}/wpa_supplicant-${PV}"

PACKAGES:prepend = "wpa-supplicant-passphrase wpa-supplicant-cli "
FILES:wpa-supplicant-passphrase = "${bindir}/wpa_passphrase"
FILES:wpa-supplicant-cli = "${sbindir}/wpa_cli"
FILES:${PN} += "${datadir}/dbus-1/system-services/* ${systemd_system_unitdir}/*"
CONFFILES:${PN} += "${sysconfdir}/wpa_supplicant.conf"

do_configure:prepend () {
    if [ -d "${WORKDIR}/${PV}" ]; then
        cp -f ${WORKDIR}/${PV}/* ${WORKDIR}/
    fi
}

do_configure () {
	${MAKE} -C wpa_supplicant clean
	install -m 0755 ${WORKDIR}/defconfig wpa_supplicant/.config

	if echo "${PACKAGECONFIG}" | grep -qw "openssl"; then
        	ssl=openssl
	elif echo "${PACKAGECONFIG}" | grep -qw "gnutls"; then
        	ssl=gnutls
	fi
	if [ -n "$ssl" ]; then
        	sed -i "s/%ssl%/$ssl/" wpa_supplicant/.config
	fi

	# For rebuild
	rm -f wpa_supplicant/*.d wpa_supplicant/dbus/*.d
}

export EXTRA_CFLAGS = "${CFLAGS}"
export BINDIR = "${sbindir}"

do_compile () {
	unset CFLAGS CPPFLAGS CXXFLAGS
	sed -e "s:CFLAGS\ =.*:& \$(EXTRA_CFLAGS):g" -i ${S}/src/lib.rules
	oe_runmake -C wpa_supplicant
}

do_install () {
	install -d ${D}${sbindir}
	install -m 755 wpa_supplicant/wpa_supplicant ${D}${sbindir}
	install -m 755 wpa_supplicant/wpa_cli        ${D}${sbindir}

	install -d ${D}${bindir}
	install -m 755 wpa_supplicant/wpa_passphrase ${D}${bindir}

	install -d ${D}${docdir}/wpa_supplicant
	install -m 644 wpa_supplicant/README ${WORKDIR}/wpa_supplicant.conf ${D}${docdir}/wpa_supplicant

	install -d ${D}${sysconfdir}
	install -m 600 ${WORKDIR}/wpa_supplicant.conf-sane ${D}${sysconfdir}/wpa_supplicant.conf

	install -d ${D}${sysconfdir}/network/if-pre-up.d/
	install -d ${D}${sysconfdir}/network/if-post-down.d/
	install -d ${D}${sysconfdir}/network/if-down.d/
	install -m 755 ${WORKDIR}/wpa-supplicant.sh ${D}${sysconfdir}/network/if-pre-up.d/wpa-supplicant
	cd ${D}${sysconfdir}/network/ && \
	ln -sf ../if-pre-up.d/wpa-supplicant if-post-down.d/wpa-supplicant

	install -d ${D}/${sysconfdir}/dbus-1/system.d
	install -m 644 ${S}/wpa_supplicant/dbus/dbus-wpa_supplicant.conf ${D}/${sysconfdir}/dbus-1/system.d
	install -d ${D}/${datadir}/dbus-1/system-services
	install -m 644 ${S}/wpa_supplicant/dbus/*.service ${D}/${datadir}/dbus-1/system-services

	if ${@bb.utils.contains('DISTRO_FEATURES','systemd','true','false',d)}; then
		install -d ${D}/${systemd_unitdir}/system
		install -m 644 ${S}/wpa_supplicant/systemd/*.service ${D}/${systemd_unitdir}/system
	fi

	install -d ${D}/etc/default/volatiles
	install -m 0644 ${WORKDIR}/99_wpa_supplicant ${D}/etc/default/volatiles
}
