#!/usr/bin/env bash

# file names & paths
tmp="$HOME"  # destination folder to store the final iso file
hostname="nuctst"
currentuser="$( whoami)"

debian_release="12.0.0"

download_location="https://cdimage.debian.org/debian-cd/${debian_release}/amd64/iso-cd"
download_file="debian-${debian_release}-amd64-netinst.iso"
new_iso_name="debian-${debian_release}-amd64-unattended.iso" # filename of the new iso file to be created


# define spinner function for slow tasks
# courtesy of http://fitnr.com/showing-a-bash-spinner.html
spinner()
{
    local pid=$1
    local delay=0.75
    local spinstr='|/-\'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# define download function
# courtesy of http://fitnr.com/showing-file-download-progress-using-wget.html
download()
{
    local url=$1
    echo -n "    "
    wget --progress=dot $url 2>&1 | grep --line-buffered "%" | \
        sed -u -e "s,\.,,g" | awk '{printf("\b\b\b\b%4s", $2)}'
    echo -ne "\b\b\b\b"
    echo " DONE"
}

# define function to check if program is installed
# courtesy of https://gist.github.com/JamieMason/4761049
function program_is_installed {
    # set to 1 initially
    local return_=1
    # set to 0 if not found
    type $1 >/dev/null 2>&1 || { local return_=0; }
    # return value
    echo $return_
}

# print a pretty header
echo
echo " +---------------------------------------------------+"
echo " |            UNATTENDED DEBIAN ISO MAKER            |"
echo " +---------------------------------------------------+"
echo

# ask if script runs without sudo or root priveleges
if [ $currentuser != "root" ]; then
    echo " you need sudo privileges to run this script, or run it as root"
    exit 1
fi

if [ -f /etc/timezone ]; then
  timezone=`cat /etc/timezone`
elif [ -h /etc/localtime ]; then
  timezone=`readlink /etc/localtime | sed "s/\/usr\/share\/zoneinfo\///"`
else
  checksum=`md5sum /etc/localtime | cut -d' ' -f1`
  timezone=`find /usr/share/zoneinfo/ -type f -exec md5sum {} \; | grep "^$checksum" | sed "s/.*\/usr\/share\/zoneinfo\///" | head -n 1`
fi

read -ep " please enter your preferred timezone: " -i "${timezone}" timezone
read -ep " please enter your preferred username: " -i "peter" username
read -sp " please enter your preferred password: " password
printf "\n"
read -sp " confirm your preferred password: " password2
printf "\n"
read -ep " Make ISO bootable via USB: " -i "yes" bootable

cd ${tmp}
if [[ ! -f ${tmp}/$download_file ]]; then
    echo -n " downloading $download_file: "
    download "$download_location/$download_file"
fi
if [[ ! -f ${tmp}/$download_file ]]; then
    echo "Error: Failed to download ISO: $download_location/$download_file"
    echo "This file may have moved or may no longer exist."
    echo
    echo "You can download it manually and move it to ${tmp}/$download_file"
    echo "Then run this script again."
    exit 1
fi

# download netson seed file
seed_file="laptop_lvm.preseed"
if [[ -f ${tmp}/${seed_file} ]]; then
  echo " deleting existing preseed file"
  rm -f ${tmp}/${seed_file}
fi
echo -n " downloading ${seed_file}: "
download "http://192.168.1.4/netinst/${seed_file}"

# install required packages
echo " installing required packages"
if [ $(program_is_installed "mkpasswd") -eq 0 ] || [ $(program_is_installed "mkisofs") -eq 0 ]; then
    (apt-get -y update > /dev/null 2>&1) &
    spinner $!
    (apt-get -y install whois genisoimage > /dev/null 2>&1) &
    spinner $!
fi
if [[ $bootable == "yes" ]] || [[ $bootable == "y" ]]; then
    if [ $(program_is_installed "isohybrid") -eq 0 ]; then
      (apt-get -y install syslinux syslinux-utils > /dev/null 2>&1) &
      spinner $!
    fi
fi

# create working folders
echo " remastering your iso file"
mkdir -p ${tmp}
mkdir -p ${tmp}/iso_org
mkdir -p ${tmp}/iso_new

# mount the image
if grep -qs ${tmp}/iso_org /proc/mounts ; then
    echo " image is already mounted, continue"
else
    (mount -o loop ${tmp}/$download_file ${tmp}/iso_org > /dev/null 2>&1)
fi

# copy the iso contents to the working directory
(cp -rT ${tmp}/iso_org ${tmp}/iso_new > /dev/null 2>&1) &
spinner $!

# set the language for the installation menu
cd ${tmp}/iso_new
echo en > ${tmp}/iso_new/isolinux/lang

# copy the preseed file to the iso
mkdir -p ${tmp}/iso_new/preseed
cp -rT ${tmp}/${seed_file} ${tmp}/iso_new/preseed/${seed_file}

# generate the password hash
pwhash=$(echo $password | mkpasswd -s -m sha-512)

# update the seed file to reflect the users' choices
# the normal separator for sed is /, but both the password and the timezone may contain it
# so instead, I am using @
sed -i "s@{{username}}@$username@g" ${tmp}/iso_new/preseed/${seed_file}
sed -i "s@{{pwhash}}@$pwhash@g" ${tmp}/iso_new/preseed/${seed_file}
sed -i "s@{{hostname}}@$hostname@g" ${tmp}/iso_new/preseed/${seed_file}
sed -i "s@{{timezone}}@$timezone@g" ${tmp}/iso_new/preseed/${seed_file}

# calculate checksum for seed file
seed_checksum=$(md5sum ${tmp}/iso_new/preseed/${seed_file})

# # add the autoinstall option to the menu
cat > ${tmp}/iso_new/isolinux/txt.cfg <<EOF  
label autoinstall
  menu label ^Autoinstall Debian
  kernel /install.amd/vmlinuz
  append initrd=/install.amd/initrd.gz auto=true priority=high preseed/file=/cdrom/preseed/${seed_file} preseed/file/checksum=${seed_checksum}  --
label install
	menu label ^Install
	kernel /install.amd/vmlinuz
	append vga=788 initrd=/install.amd/initrd.gz --- quiet 
EOF

# Grub config
cat > ${tmp}/iso_new/boot/grub/grub.cfg <<EOF
if [ x\$feature_default_font_path = xy ] ; then
   font=unicode
else
   font=\$prefix/font.pf2
fi

if loadfont \$font ; then
  set gfxmode=800x600
  set gfxpayload=keep
  insmod efi_gop
  insmod efi_uga
  insmod video_bochs
  insmod video_cirrus
  insmod gfxterm
  insmod png
  terminal_output gfxterm
fi

if background_image /isolinux/splash.png; then
  set color_normal=light-gray/black
  set color_highlight=white/black
elif background_image /splash.png; then
  set color_normal=light-gray/black
  set color_highlight=white/black
else
  set menu_color_normal=cyan/blue
  set menu_color_highlight=white/blue
fi

insmod play
play 960 440 1 0 4 440 1
set theme=/boot/grub/theme/1
menuentry --hotkey=a '... Automated install' {
    set background_color=black
    timeout=5
    linux    /install.amd/vmlinuz append initrd=/install.amd/initrd.gz auto=true priority=high preseed/file=/cdrom/preseed/${seed_file} quiet ---
    initrd   /install.amd/initrd.gz
}
menuentry --hotkey=r '... Rescue mode' {
    set background_color=black
    linux    /install.amd/vmlinuz vga=788 rescue/enable=true --- quiet 
    initrd   /install.amd/initrd.gz
}
EOF

echo " creating the remastered iso"
cd ${tmp}/iso_new
(mkisofs -D -r -V "DEBIAN_AUTO" -cache-inodes -J -l -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -o ${tmp}/$new_iso_name . > /dev/null 2>&1) &
spinner $!

# make iso bootable (for dd'ing to  USB stick)
if [[ $bootable == "yes" ]] || [[ $bootable == "y" ]]; then
    isohybrid ${tmp}/$new_iso_name
fi

# cleanup
umount ${tmp}/iso_org
rm -rf ${tmp}/iso_new
rm -rf ${tmp}/iso_org
rm -rf ${tmp}html


# print info to user
echo " -----"
echo " finished remastering your ubuntu iso file"
echo " the new file is located at: ${tmp}/$new_iso_name"
echo " your username is: $username"
echo " your password is: $password"
echo " your hostname is: $hostname"
echo " your timezone is: $timezone"
echo

# unset vars
unset username
unset password
unset hostname
unset timezone
unset pwhash
unset download_file
unset download_location
unset new_iso_name
unset tmp
unset seed_file