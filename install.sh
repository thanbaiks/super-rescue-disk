#!/usr/bin/env bash

set -e

DARKGRAY=$'\e[1;30m'
RED=$'\e[0;31m'
LIGHTRED=$'\e[1;31m'
GREEN=$'\e[0;32m'
YELLOW=$'\e[1;33m'
BLUE=$'\e[0;34m'
PURPLE=$'\e[0;35m'
LIGHTPURPLE=$'\e[1;35m'
CYAN=$'\e[0;36m'
WHITE=$'\e[1;37m'
SET=$'\e[0m'

_pause() {
	read -p "${YELLOW}Press [enter] to continue${SET}"
}

check_binaries() {
	local bins=(sgdisk mkfs.fat grub-install rsync)
	hash ${bins[*]} &> /dev/null || return 1
}

check_grub_platforms() {
	for x in i386-pc x86_64-efi; do
		if ! [ -d /usr/lib/grub/${x} ]; then return 1; fi
	done
	return 0
}

initial_disk() {
	local disk=$1
	if ! [ -e "/dev/${disk}" ]; then
		echo "${RED}Error: Invalid disk (${disk})${SET}"
	fi
	echo -e "${RED}Warning! Warning!\nAll data on ($disk) will be lost and unrecoverable.\nAre you sure to continue (y/N)?${SET}"
	read answer
	if [ "$answer" != "y" -a "$answer" != "Y" ]; then
		return 0
	fi
	tmp=$(mktemp)
	sgdisk -Zo \
        -n 1:2048:+300M -t 1:ef00 -c 1:"EFI" \
	    -n 2:+0:+10M -t 2:ef02 -c 2:"BIOS Boot" \
	    -n 3:+0:+2G -t 3:0700 -c 3:"Rescue" \
	    -n 4:+0:-0 -t 4:0700 -c 4:"Data" \
	    -h "1:3:4" \
	    /dev/$disk 2&>$tmp
	if [ $? -ne 0 ]; then
		echo -e "${RED}Failed to run sgdisk on selected disk. Please see the following log${DARKGRAY}"
		cat $tmp
		echo -e "${SET}"
		_pause
		return 1
	fi
	partprobe
	echo -e "${GREEN}Formatting partitions...${SET}"
	mkfs.fat -F 32 -n "EFI" "/dev/${disk}1" > $tmp 2>&1 &&\
	mkfs.fat -F 32 -n "Rescue" "/dev/${disk}3" > $tmp 2>&1 &&\
	mkfs.ntfs -f -L "Data" "/dev/${disk}4" > $tmp 2>&1
	if [ $? -ne 0 ]; then
		echo -e "${RED}Some partitions cannot be formated${DARKGRAY}"
		cat $tmp
		echo -e "${SET}"
		return 1
	fi
	echo -e "${GREEN}Disk initialized successfully!${SET}"
	_pause
	return 0
}

menu() {
	local disk
	local answer
	while true; do
		clear
		answer=''
		echo -e "${GREEN}[BachNX Edition]${SET} Super rescue disk creator"
		echo -e "-------------------------------------------"
		if [ -z "${disk}" ]; then
			# Prompt disk select
			local default
			echo "Searching for disks..."
			for x in /dev/sd*; do
				x=`basename $x`
				if expr match "${x}" '[a-z]*$'>/dev/null; then
					echo "Found ${CYAN}${x}${SET}"
					default=$x
				fi
			done
			read -p "Select your disk (${default}): " -i "${default}" answer
			answer=${answer:-$default}
			if ! [ -e /dev/${answer} ]; then
				echo "${RED}Selected disk not valid (${answer})${SET}"
				_pause
			else
				disk=$answer
			fi
		else
			echo    "Current disk: ${CYAN}${disk}${SET}.${DARKGRAY}"
			sgdisk -p "/dev/${disk}"
			echo -e "${SET}\n"
			echo    "Please select an item:"
			echo    "[i] Initialize disk (detroy all data)"
			echo    "[g] Install dual-grub on disk"
			echo    "[c] Copy File to disk"
			echo    "[d] Choose another disk"
			echo    "[a] Do everything (i+g+c)"
			echo    "[q] Quit"
			read -p "    Your answer (lowercase): " -n 1 answer
			echo
			case $answer in
				d)
					disk=''
					;;
				i)
					initial_disk $disk
					if [ $? -ne 0 ]; then
						exit $?
					fi
					;;
				q)
					echo "${CYAN}Bye bye${SET}"
					exit 0
					;;
				*)
					if [ -n "${answer}" ]; then
						echo "${RED}Invalid  command (${answer}).${SET}"
						_pause
					fi
				;;
			esac
		fi
	done
}

#
# Pre-flight checks
#

if [ $(id -u) -ne 0 ]; then
	echo "${RED}You must be root to perform this action.${SET}\n"
	exit 1
elif ! check_binaries; then
	echo "${RED}Some binary not found.${SET}\n" ""
	exit 1
elif ! check_grub_platforms; then
	echo "${RED}Some GRUB platforms are missing.${SET}\n"
	exit 1
fi

menu
# initial_disk sdb