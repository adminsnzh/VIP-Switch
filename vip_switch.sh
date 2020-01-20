#!/bin/bash
# Description: To online and offline VIP.
#
# SID
# ---
# H1P	hana1pdb	10.10.244.1	bond0:0
# H2P	hana2pdb	10.10.244.2	bond0:1
# H3P	hana3pdb	10.10.244.3	bond0:2
#
#set -x

usage() {
	echo "Usage: $0 <SID> {online|offline}"
	echo
	RETVAL=2
}

# verify input attributes
if [[ $# -lt 2 ]]; then
	usage
	RETVAL=2
	exit $RETVAL
fi

SID=$1
ACTION=$2
SID_EXIST=0
RETVAL=0
declare -A IF_LIST
IF_LIST+=([H1P]="bond0:0")
IF_LIST+=([H2P]="bond0:1")
IF_LIST+=([H3P]="bond0:2")
#IF_LIST+=([TST1]="ens32:0")
#IF_LIST+=([TST2]="ens32:1")

for S in ${!IF_LIST[@]}; do
#    echo $S ${IF_LIST[${S}]}
    if [[ "$SID" == "$S" ]]; then
#    	echo "$SID match interface ${IF_LIST[$S]}"
    	IF=${IF_LIST[$S]}
    	SID_EXIST=1
    fi
done
if [[ $SID_EXIST -eq 1 ]]; then
	IP=$(ip addr | awk '/secondary / {split($2,var,"/*"); print $8,var[1]}' | grep $IF)
else
	RETVAL=2
	ERRSTR="Unknown SID $SID."
	echo $ERRSTR
	exit $RETVAL
fi


if_stat() {
# STAT
# 0 VIP is up and response to ping.
# 1 VIP is down.
# 2 VIP not found.
# 3 VIP is running on other node.

	IP=$(ip addr | awk '/secondary / {split($2,var,"/*"); print $8,var[1]}' | grep $IF | awk '{ print $2 }')
	if [[ "$IP" == "" ]]; then
		if [[ -f /etc/sysconfig/network-scripts/ifcfg-$IF ]]; then
			IP=$(grep -i "^IPADDR" /etc/sysconfig/network-scripts/ifcfg-$IF | awk -F= '{ print $2 }')
			ping -c 3 -q $IP > /dev/null
			if [[ $? -eq 0 ]]; then
				local STAT=3
				RETVAL=2
				ERRSTR="$ERRSTR;VIP is running on other node."
			else
				local STAT=1
			fi
		else
			local STAT=2
			RETVAL=2
			ERRSTR="$ERRSTR;VIP profile not found."
		fi
	else
		ping -c 3 -q $IP > /dev/null
		if [[ $? -eq 0 ]]; then
			local STAT=0
		else
			local STAT=1
		fi
	fi
#	echo IF_STAT=$STAT
	return $STAT
}


print_errstr() {
	if [[ "$1" != "" ]]; then
		echo "$@" | tr ';' '\n' | grep -v "^$" | while read ERR; do
			echo -e $ERR
		done
	fi
}


case "$2" in
	"online") # bring interface online
		echo "Try to bring $SID VIP online."
		if_stat
		STAT=$?
		if [[ $STAT -eq 1 ]]; then
			ifup $IF
			if [[ $? -eq 0 ]]; then
				echo "$SID VIP is up!"
			else
				RETVAL=1
				ERRSTR="$ERRSTR;Failed to start $SID VIP."
			fi
		elif [[ $STAT -eq 0 ]]; then
			RETVAL=2
			ERRSTR="$ERRSTR;$SID is already up."
		fi
		;;
	"offline") # bring interface offline
		echo "Try to bring $SID VIP offline."
		if_stat
		STAT=$?
		if [[ $STAT -eq 0 ]]; then
			ifdown $IF
			if [[ $? -eq 0 ]]; then
				echo "$SID VIP is down!"
			else
				RETVAL=1
				ERRSTR="$ERRSTR;Failed to stop $SID VIP."
			fi
		elif [[ $STAT -eq 1 ]]; then
			RETVAL=2
			ERRSTR="$ERRSTR;$SID is already down."
		fi
		;;
	*)
		usage
		;;
esac

print_errstr $ERRSTR
exit $RETVAL
