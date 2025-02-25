#!/bin/sh

dotfiles="https://github.com/duolok/oblivion.git"

get_user() {
	name=$(whiptail --inputbox "Enter a name for the user" 10 60 3>&1 1>&2 2>&3 3>&1) || exit 1

	while ! echo "$name" | grep -q "^[a-z_][a-z0-9_-]*$"; do
		name=$(whiptail --nocancel --inputbox "Username not valid. Give a username beginning with a letter, with only lowercase letters, - or _." 10 60 3>&1 1>&2 2>&3 3>&1)
	done

	pass1=$(whiptail --nocancel --passwordbox "Enter a password." 10 60 3>&1 1>&2 2>&3 3>&1)
	pass2=$(whiptail --nocancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)

	while ! [ "$pass1" = "$pass2" ]; do
		unset pass2
		pass1=$(whiptail --nocancel --passwordbox "Passwords do not match.\\n\\nEnter password again." 10 60 3>&1 1>&2 2>&3 3>&1)
		pass2=$(whiptail --nocancel --passwordbox "Retype password." 10 60 3>&1 1>&2 2>&3 3>&1)
	done
}

user_exists() {
	! { id -u "$name" >/dev/null 2>&1; } ||
		whiptail --title "WARNING" --yes-button "CONTINUE" \
			--no-button "No wait..." \
			--yesno "The user \`$name\` already exists on this system. LARBS can install for a user already existing, but it will OVERWRITE any conflicting settings/dotfiles on the user account.\\n\\nLARBS will NOT overwrite your user files, documents, videos, etc., so don't worry about that, but only click <CONTINUE> if you don't mind your settings being overwritten.\\n\\nNote also that LARBS will change $name's password to the one you just gave." 14 70
}

refresh_keys() {
	case "$(readlink -f /sbin/init)" in
	*systemd*)
		whiptail --infobox "Refreshing Arch Keyring..." 7 40
		pacman --noconfirm -S archlinux-keyring >/dev/null 2>&1
		;;
	*)
		whiptail --infobox "Enabling Arch Repositories for more a more extensive software collection..." 7 40
		pacman --noconfirm --needed -S \
			artix-keyring artix-archlinux-support >/dev/null 2>&1
		grep -q "^\[extra\]" /etc/pacman.conf ||
			echo "[extra]
Include = /etc/pacman.d/mirrorlist-arch" >>/etc/pacman.conf
		pacman -Sy --noconfirm >/dev/null 2>&1
		pacman-key --populate archlinux >/dev/null 2>&1
		;;
	esac

}

install_dependencies() {
	for x in curl ca-certificates base-devel git ntp zsh tmux vim neovim; do
		whiptail --title "Oblivion install" \
			--infobox "Installing \`$x\` which is required to install and configure other programs." 8 70
		installpkg "$x"
	done
}

sync_time() {
	whiptail --title "Oblivion install" \
		--infobox "Synchronizing system time to ensure successful and secure installation of software..." 8 70
	ntpd -q -g >/dev/null 2>&1
}

add_user_and_pass() {
	whiptail --infobox "Adding user \"$name\"." 7 50
	useradd -m -g wheel -s /bin/zsh "$name" >/dev/null 2>&1 || 
		usermod -a -G wheel "$name" && mkdir -p /home/"$name" && chown "$name":wheel /home"$name"
	export repodir="/home/$name/.local/src"
	mkidr -p "$repodir"
	chown -R "$name":wheel "$(dirname "$repodir")"
	echo "$name:$pass1" | chpasswd
	unset pass1 pass2
}

safety_configure_sudoers() {
	[ -f /etc/sudoers.pacnew ] && cp /etc/sudoers.pacnew /etc/sudoers
}

better_user() {
	trap 'rm -f /etc/sudoers.d/oblivion-temp' HUP INT QUIT TERM PWR EXIT
	echo "%wheel ALL=(ALL) NOPASSWD: ALL
	Defaults:%wheel runcwd=*" >/etc/sudoers.d/oblivion-temp
}

# colorful and concurrent patch
better_pacman() {
	grep -q "ILoveCandy" /etc/pacman.conf || sed -i "/#VerbosePkgLists/a ILoveCandy" /etc/pacman.conf
	sed -Ei "s/^#(ParallelDownloads).*/\1 = 5/;/^#Color$/s/#//" /etc/pacman.conf
}

pacman --noconfirm --needed -Sy libnewt || error "Are you sure you're running this as the root user, are on an Arch-based distribution and have an internet connection?"

get_user || "Installation cancelled."

user_exists || "Installation cancelled."

install_dependencies

sync_time

add_user_and_pass 

safety_configure_sudoers

better_user

better_pacman

# use all cores
sed -i "s/-j2/-j$(nproc)/;/^#MAKEFLAGS/s/^#//" /etc/makepkg.conf


