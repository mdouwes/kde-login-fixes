#!/usr/bin/bash
# Install kde-login-fixes system-wide. Run as root:  sudo ./install.sh
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
[ "$(id -u)" = 0 ] || { echo "run as root (sudo ./install.sh)" >&2; exit 1; }

# Migrate from the pre-rename install (kde-lockscreen-patch): revert it with its
# own script so the shipped files come back, then install fresh below.
OLD=/usr/local/sbin/kde-lockscreen-patch
if [ -x "$OLD" ]; then
    echo "Found previous kde-lockscreen-patch install, reverting it first."
    "$OLD" revert
    rm -f "$OLD" /etc/dnf/libdnf5-plugins/actions.d/kde-lockscreen-patch.actions
    rm -rf /usr/local/share/kde-lockscreen-patch
fi

DATA=/usr/local/share/kde-login-fixes
install -d "$DATA/patches" "$DATA/pam" "$DATA/backup"
install -m 0644 patches/*.patch "$DATA/patches/"
install -m 0644 pam/kde pam/kde-fingerprint "$DATA/pam/"
install -m 0755 bin/kde-login-fixes /usr/local/sbin/kde-login-fixes

# dnf5 hook so the QML patch survives plasma-desktop upgrades
if ! rpm -q libdnf5-plugin-actions >/dev/null 2>&1; then
    dnf5 -y install libdnf5-plugin-actions
fi
install -d /etc/dnf/libdnf5-plugins/actions.d
install -m 0644 dnf/kde-login-fixes.actions /etc/dnf/libdnf5-plugins/actions.d/kde-login-fixes.actions

/usr/local/sbin/kde-login-fixes apply
echo
/usr/local/sbin/kde-login-fixes status
echo
echo "Done. Takes effect the next time the screen locks (no logout needed)."
