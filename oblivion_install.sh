#!/bin/sh

dotfiles_repository="https://github.com/duolok/oblivion.git"
galaxy_nvim_repository="https://github.com/duolok/galaxy-nvim.git"
repo_branch="master"
package_manager="yay"
export TERM=ansi

install_package() {
	pacman --noconfirm --needed -S "$1" >/dev/null 2>&1
}

# log to stderr and exit with failure.
error() {
	printf "%s\n" "$1" >&2
	exit 1
}

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
		whiptail --title "Oblivion Install" \
			--infobox "Installing \`$x\` which is required to install and configure other programs." 8 70
		install_package "$x"
	done
}

sync_time() {
	whiptail --title "Oblivion Install" \
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

manual_install() {
	pacman -Qq "$1" && return 0
	whiptail --infobox "Installing \"$1\" manually." 7 50
	sudo -u "$name" mkdir -p "$repodir/$1"
	sudo -u "$name" git -C "$repodir" clone --depth 1 --single-branch \
		--no-tags -q "https://aur.archlinux.org/$1.git" "$repodir/$1" ||
		{
			cd "$repodir/$1 ||" || exit 1
			sudo -u "$name" git pull --force origin master
		}
	cd "$repodir/$1" || exit 1
	sudo -u "$name" -D "$repodir/$1" \
		makepkg --noconfirm -si >/dev/null 2>&1 || return 1
}

aur_install() {
	whiptail --title "Oblivion Install" \
		--infobox "Installing \`$1\` ($n of $total) from the AUR. $1 $2" 8 70
	echo "$aurinstalled" | grep -q "^$1$" && return 1
	sudo -u "$name" $package_manager -S --no-confirm "$1" >/dev/null 2>&1
}

git_make_install() {
	progname="${1##*/}"
	progname="${progname%.git}"
	dir="$repodir/$progname"
	whiptail --title "Oblivion Install" \
		--infobox "Installing  \`$progname\` ($n of $total) with git and make. $1 $2" 8 70
	sudo -u "$name" git -C "$repodir" clone --depth 1 --single-branch \
		--no-tags -q "$1" "$dir" ||
		{
			cd "$dir" || return 1
			sudo -u "$name" git pull --force origin master
		}

	cd "$dir" || exit 1
	make >/dev/null 2>&1
	make install >/dev/null 2>&1
	cd /tmp || return 1
}

pip_install() {
	whiptail --title "Oblivion Install" \
		--infobox "Installing Python pacakge \`$1\` ($n of $total). $1 $2" 8 70
	[ -x "$(command -v "pip")" ]  || install_package python-pip >/dev/null 2>&1
	yes | pip install "$1"
}

main_install() {
	whiptail --title "Oblivion Install" \
		--infobox "Installing Python pacakge \`$1\` ($n of $total). $1 $2" 8 70
	install_package "$1"
}

put_git_repo() {
	whiptail --infobox "Downloading and installing config files..." 7 60
	[ -z "$3" ] && branch="master" || branch="$repo_branch"
	dir=$(mktemp -d)
	[ ! -d "$2" ] && mkdir -p "$2"
	chown "$name":wheel "$dir" "$2"
	sudo -u "$name" git -C "$repodir" clone --depth 1 \
		--single-branch --no-tags -q --recursive -b "$branch" \
		--recurse-submodules "$1" "$dir"
	sudo -u "$name" cp -rfT "$dir" "$2"
}

install_loop() {
	([ -f "$progsfile" ] && cp "$progsfile" /tmp/progs.csv) ||
		curl -Ls "$progsfile" | sed '/^#/d' >/tmp/progs.csv
	total=$(wc -l </tmp/progs.csv)
	aurinstalled=$(pacman -Qqm)
	while IFS='|' read -r tag program comment; do
		n=$((n + 1))
		echo "$comment" | grep -q "^\".*\$" && comment="$(echo "$comment" | sed -E "s/(^\"|\"$)//g")"
		case "$tag" in
			"aur") aur_install "$program" "#comment" ;;
			"git") git_make_install "$program" "$comment" ;;
			"pip") pip_install "$program" "$comment" ;;
			*) main_install "$program" "$comment" ;;
		esac
	done </tmp/progs.csv
}

galaxy_install() {
	local_dir="$HOME/nvim"
	mkdir -p "$(dirname "$local_dir")"

	if [ ! -d "$install_dir/.git" ]; then
		git clone --depth 1 --single-branch --no-tags "$galaxy_nvim_repository" "$install_dir" ||
			{
				echo "Failed to clone Galaxy NVim repository."
				return 1
			}
	else
		cd "$install_dir" || return 1
		git pull --force origin master
	fi
	cd "$install_dir" || return 1
	./install_complex
	rm -rf local_dir
}


pacman --noconfirm --needed -Sy libnewt || error "Are you sure you're running this as the root user, are on an Arch-based distribution and have an internet connection?"

get_user || "Installation cancelled."

user_exists || "Installation cancelled."3:with

install_dependencies

sync_time

add_user_and_pass

safety_configure_sudoers

better_user

better_pacman

# use all cores
sed -i "s/-j2/-j$(nproc)/;/^#MAKEFLAGS/s/^#//" /etc/makepkg.conf

manual_install $package_manager || error "Failed to install AUR helper."

$package_manager -Y --save --devel

install_loop

put_git_repo "$dotfiles_repository" "/home/$name" "$repo_branch"
rm -rf "/home/$name/.git/" "/home/$name/README.md"

galaxy_install || "Galaxy nvim installation didn't work."
