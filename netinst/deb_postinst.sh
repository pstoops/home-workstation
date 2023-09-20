#!/bin/bash
IP="192.168.1.99"
NM="255.255.255.0"
GW="192.168.1.1"
NS="192.168.1.80"
#NIC=$(/bin/nmcli dev | grep ethernet | awk '{print $1}')
NIC=$(/sbin/ip li sh | grep 'state UP' | head -1 | awk '{print $2}' | sed -e 's/://')
#echo "deb_postinst: found NIC ${NIC}" >> /root/postinstall.log
echo -e "auto lo ${NIC} \niface lo inet loopback\n\niface ${NIC} inet static\n\t address ${IP}\n\t netmask ${NM}\n\t gateway ${GW}\n\t dns-nameservers ${NS}" > /etc/network/interfaces
#echo "deb_postinst: wrote interfaces files" >> /root/postinstall.log
echo "nuctst.home.taurus" > /etc/hostname