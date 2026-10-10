#!/usr/bin/bash
# Remove the Plasma lock screen patches and restore the shipped files. Run as root.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "run as root (sudo ./uninstall.sh)" >&2; exit 1; }
if [ -x /usr/local/sbin/kde-login-fixes ]; then
    /usr/local/sbin/kde-login-fixes revert
fi
rm -f /etc/dnf/libdnf5-plugins/actions.d/kde-login-fixes.actions
rm -f /usr/local/sbin/kde-login-fixes
rm -rf /usr/local/share/kde-login-fixes
echo "Removed. (libdnf5-plugin-actions package left installed.)"
