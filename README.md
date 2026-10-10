# kde-login-fixes

Fixes for unlocking the KDE Plasma lock screen on Fedora: no more pressing
Enter before you can scan your finger or type your password, no more vanishing
fingerprint option, and any key or tap dismisses the Unlock screen if it ever
shows up.

On Fedora with authselect's `with-fingerprint` feature, the Plasma 6.7 lock
screen has two annoying habits:

1. when it wakes it shows an **Unlock** button and waits for Enter before you
   can scan your finger or type your password;
2. the *"(or scan your fingerprint on the reader)"* hint sometimes vanishes and
   fingerprint unlock is dead until the next lock.

kde-login-fixes fixes both with two PAM files and a tiny QML patch. No rebuilds.
After installing, the lock screen comes up ready: scan your finger or type your
password straight away. If the Unlock screen ever does appear, any key or a tap
dismisses it.

Tested on Fedora 44, Plasma 6.7.5 (kscreenlocker 6.7.5, plasma-desktop
6.7.5), fprintd 1.94.5, dnf5 5.4.

## Install

```sh
sudo ./install.sh     # installs, enables the dnf5 hook, applies
sudo kde-login-fixes status   # what is currently applied
sudo ./uninstall.sh   # restores the shipped files
```

Takes effect on the next lock; every lock starts a fresh greeter.

## Why it happens

kscreenlocker's greeter (6.7) runs three PAM conversations in parallel when the
lock screen wakes: the interactive `kde` service for the password, and the
non-interactive `kde-fingerprint` and `kde-smartcard` services.

* Fedora's `/etc/pam.d/kde` is a substack of `password-auth`, which with
  `with-fingerprint` **also** contains `pam_fprintd`. So `kde` and
  `kde-fingerprint` race for the one reader.
* In `password-auth`, `pam_fprintd` sits in front of `pam_unix`, so the `kde`
  service gets stuck on the reader and never issues a password prompt. The
  greeter's `hadPrompt` stays false, and it loads `NoPasswordUnlock.qml` (the
  Unlock button that needs Enter), a screen meant for passwordless accounts.
  Only after Enter can you scan or type your password.
* The loser gets "device already claimed" and returns `PAM_AUTHINFO_UNAVAIL`.
  `PamWorker::authenticate()` turns that into a permanent `m_unavailable`, so
  the fingerprint authenticator is dead for the rest of the lock and the hint
  disappears.
* Independently, `pam_fprintd` gives up after 30 s and returns the same
  `PAM_AUTHINFO_UNAVAIL`. Don't touch the reader within 30 s of waking the
  screen and fingerprint is gone until the next lock.

## What kde-login-fixes changes

| File | Owner | Change |
|------|-------|--------|
| `/etc/pam.d/kde` | plasma-workspace, `%config(noreplace)` | The `password-auth` stack with `pam_fprintd` removed. The password service always prompts, fingerprint only runs through `kde-fingerprint`. |
| `/etc/pam.d/kde-fingerprint` | plasma-workspace, `%config(noreplace)` | `pam_fprintd timeout=86400`, listed 8x with `[success=done default=ignore]`, so a timeout, a sensor error after suspend or 3 bad scans fall through to a fresh attempt. 24 bad scans before password-only. |
| `/usr/share/plasma/shells/org.kde.plasma.desktop/contents/lockscreen/NoPasswordUnlock.qml` | plasma-desktop | Any key press or tap calls `Qt.quit()`. Safety net; with the PAM fix this screen no longer appears for fingerprint unlocks. |

The long timeout is safe: the greeter exits with `_exit(0)` the moment it
unlocks, which drops its D-Bus connection and releases the reader.

## Surviving updates

* The two PAM files are RPM `noreplace` config, so package updates never
  overwrite them. If Fedora changes its defaults you get a `.rpmnew` next to
  them and `kde-login-fixes apply` prints a note.
* The QML file is not config, so `install.sh` installs
  `libdnf5-plugin-actions` and a hook (`dnf/kde-login-fixes.actions`) that runs
  `kde-login-fixes apply` after any transaction that upgrades `plasma-desktop` or
  `plasma-workspace`. `apply` is idempotent and refuses to touch a file the
  patch no longer fits, in which case it warns and leaves the shipped file.

## Layout

```
bin/kde-login-fixes           apply | revert | status  (installed to /usr/local/sbin)
pam/kde               replacement /etc/pam.d/kde
pam/kde-fingerprint   replacement /etc/pam.d/kde-fingerprint
patches/*.patch       unified diff against the plasma-desktop shell package
dnf/kde-login-fixes.actions   dnf5 actions-plugin hook
install.sh / uninstall.sh
```

`bin/kde-login-fixes` honours `KLP_ROOT` (alternative root) and `KLP_DATA` (where
`patches/` and `pam/` live, default `/usr/local/share/kde-login-fixes`) so the
apply/revert logic can be exercised on a throwaway copy of the files.

## Debugging

Greeter debug logging shows every PAM message and state change:

```
# ~/.config/QtProject/qtlogging.ini
[Rules]
kscreenlocker_greet.debug=true
```

then lock and watch `journalctl -f _COMM=kscreenlocker_greet`.

To try a modified shell package without locking the real session:

```
/usr/libexec/kscreenlocker_greet --testing --shell /path/to/package/copy
```

(It is a real greeter: typing your password into it unlocks and closes it.)

## Caveats

* `/etc/pam.d/kde` no longer follows authselect. If you change the profile
  (add SSSD, etc.), mirror the new `auth` lines in `pam/kde`.
* Upstream reworked the greeter's PAM handling after 6.7 (lands in Plasma 6.8).
  When Fedora ships it, re-check whether the `kde-fingerprint` workaround is
  still needed; `kde-login-fixes status` and the `.rpmnew` note are the signals.

## License

MIT, see `LICENSE`. The QML patch modifies a GPL-2.0-or-later file from
plasma-desktop and stays under that license.
