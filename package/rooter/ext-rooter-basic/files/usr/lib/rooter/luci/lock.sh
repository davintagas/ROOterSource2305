#!/bin/sh

ROOTER=/usr/lib/rooter
ROOTER_LINK="/tmp/links"

log() {
	modlog "Lock Band $CURRMODEM" "$@"
}

restart=$(uci -q get custom.bandlock.restart)
if [ -z "$restart" ]; then
	restart="1"
fi
RESTART="1"
if [ "$restart" = "0" ]; then
	RESTART="0"
fi

ifname1="ifname"
if [ -e /etc/newstyle ]; then
	ifname1="device"
fi

fibdecode() {
	j=$1
	tdec=$2
	mod=$3
	length=${#j}
	jx=$j
	length=${#jx}

	str=""
	i=$((length-1))
	while [ $i -ge 0 ]
	do
		dgt="0x"${jx:$i:1}
		DecNum=`printf "%d" $dgt`
		Binary=
		Number=$DecNum
		while [ $DecNum -ne 0 ]
		do
			Bit=$(expr $DecNum % 2)
			Binary=$Bit$Binary
			DecNum=$(expr $DecNum / 2)
		done
		if [ -z $Binary ]; then
			Binary="0000"
		fi
		len=${#Binary}
		while [ $len -lt 4 ]
		do
			Binary="0"$Binary
			len=${#Binary}
		done
		revstr=""
		length=${#Binary}
		ii=$((length-1))
		while [ $ii -ge 0 ]
		do
			revstr=$revstr${Binary:$ii:1}
			ii=$((ii-1))
		done
		str=$str$revstr
		i=$((i-1))
	done

	len=${#str}
	ii=0
	lst=""
	sep=","
	hun=101
	if [ $mod = "1" ]; then
		sep=":"
		hun=1
	fi
	if [ $mod = "2" ]; then
		sep=","
		hun=1
	fi
	while [ $ii -lt $len ]
	do
		bnd=${str:$ii:1}
		if [ $bnd -eq 1 ]; then
			if [ $tdec -eq 1 ]; then
				jj=$((ii+hun))
			else
				if [ $ii -lt 9 ]; then
					jj=$((ii+501))
				else
					jj=$((ii+5001))
				fi
			fi
			if [ -z "$lst" ]; then
				lst=$jj
			else
				lst=$lst$sep$jj
			fi
		fi
		ii=$((ii+1))
	done
	if [ -z $lst ]; then
		lst="0"
	fi
}

encode() {
	maskz=$1
	length=${#maskz}
	i=0
	ii=1
	lst=""
	ij=$((length-1))
	while [ $i -le $ij ]
	do
		dgt=${maskz:$i:1}
		if [ $dgt == "1" ]; then
			lst=$lst$ii" "
		fi
		i=$((i+1))
		ii=$((ii+1))
	done
	maskz=$(encodemask $lst)
	maskz=$(echo $maskz | sed 's/^0*//')
}

maskx=$1
mask64=$(echo "$maskx""," | cut -c1-64 | cut -d, -f1)
maskl2=$(echo ${maskx:64}"," | cut -d, -f1)
maskc=$(echo "$maskx" | grep ",")
if [ ! -z "$maskc" ]; then
	mask=$(echo $maskx"," | cut -d, -f1)
	mask5g=$(echo $maskx"," | cut -d, -f2)
	mask5gsa=$(echo $maskx"," | cut -d, -f3)
else
	mask=$maskx
	mask5g=""
	mask5gsa=""
fi

#log "$mask"
#log "$mask5g"
#log "$mask5gsa"
maskxx=$mask
mask5gxx=$mask5g
mask5gsaxx=$mask5gsa

encode $mask
mask=$maskz
encode $mask5g
mask5g=$maskz
encode $mask5gsa
mask5gsa=$maskz
encode $mask64
mask64=$maskz
encode $maskl2
if [ -z $maskz ]; then
	maskl2="0"
else
	maskl2=$maskz
fi
if [ -z $mask64 ]; then
	mask64="0"
fi

if [ -z "$2" ]; then
	CURRMODEM=$(uci get modem.general.miscnum)
else
	CURRMODEM=1
fi
COMMPORT="/dev/ttyUSB"$(uci get modem.modem$CURRMODEM.commport)
CPORT=$(uci -q get modem.modem$CURRMODEM.commport)
model=$(uci get modem.modem$CURRMODEM.model)
uVid=$(uci get modem.modem$CURRMODEM.uVid)
uPid=$(uci get modem.modem$CURRMODEM.uPid)
GW=$(uci -q get modem.modem$CURRMODEM.GW)

export TIMEOUT="5"
case $uVid in
	"2c7c" )
		MODT="1"
		#if [ -z "$2" ]; then
		#	RESTART="1"
		#fi
		M5=""
		M2='AT+QCFG="band",0,'$mask',0'
		if [ $uPid = 0620 ]; then
			EM20=$(echo $model | grep "EM20")
			if [ -z "$EM20" ]; then #EM160
				if [ ! -z $mask ]; then
					fibdecode $mask 1 1
				else
					lst="0"
				fi
				M2='AT+QNWPREFCFG="lte_band",'$lst
			else # Fake EM160 RM500
				if [ -e /etc/qfake ]; then
					if [ ! -z $mask ]; then
						fibdecode $mask 1 1
					else
						lst="0"
					fi
					M2F='AT+QNWPREFCFG="lte_band",'$lst
					if [ ! -z $mask5g ]; then
						fibdecode $mask5g 1 1
					else
						lst="0"
					fi
					M5F='AT+QNWPREFCFG="nsa_nr5g_band",'$lst
					NET=$(uci -q get modem.modem$CURRMODEM.netmode)
					if [ $NET = "9" ]; then
						M5F='AT+QNWPREFCFG="nr5g_band",'$lst
					fi
					log " "
					log "Fake LTE Locking Cmd :  $M2F"
					log "Fake 5G Locking Cmd :  $M5F"
					log " "
					#rm -f /tmp/bmask
					exit 0
				fi
			fi
		fi
		if [ $uPid = 030b ]; then
			if [ ! -z $mask ]; then
				fibdecode $mask 1 1
			else
				lst="0"
			fi
			M2='AT+QNWPREFCFG="lte_band",'$lst
		fi
		if [ $uPid = 6005 ]; then
			M2='AT+QCFG="band",0,'$mask
		fi
		if [ $uPid = 0306 ]; then
			RESTART="1"
		fi
		if [ $uPid = 0800 -o $uPid = 0900 -o $uPid = 0801 -o $uPid = 0122 ]; then
			if [ ! -z "$mask" ]; then
				fibdecode $mask 1 1
			else
				lst="0"
			fi
			M2='AT+QNWPREFCFG="lte_band",'$lst
			if [ ! -z "$mask5g" ]; then
				fibdecode $mask5g 1 1
			else
				lst="0"
			fi
			M5='AT+QNWPREFCFG="nsa_nr5g_band",'$lst
			if [ ! -z "$mask5gsa" ]; then
				fibdecode $mask5gsa 1 1
			else
				lst="0"
			fi
			M6='AT+QNWPREFCFG="nr5g_band",'$lst
		fi
		log " "
		log "Locking Cmd : $M2"
		log "Locking Cmd : $M5"
		log "Locking Cmd : $M6"
		log " "
		
		ATCMDD="AT"
		NOCFUN=$uVid
		OX=$($ROOTER/gcom/gcom-locked "$COMMPORT" "run-at.gcom" "$CURRMODEM" "$M2")
		if [ ! -z "$M5" ]; then
			OX5=$($ROOTER/gcom/gcom-locked "$COMMPORT" "run-at.gcom" "$CURRMODEM" "$M5")
		fi
		if [ ! -z "$M6" ]; then
			OX6=$($ROOTER/gcom/gcom-locked "$COMMPORT" "run-at.gcom" "$CURRMODEM" "$M6")
		fi
		log "Locking Cmd Response : $OX"
		log "Locking Cmd Response : $OX5"
		log "Locking Cmd Response : $OX6"
		log " "
		if [ $RESTART = "1" ]; then
			OX=$($ROOTER/gcom/gcom-locked "$COMMPORT" "run-at.gcom" "$CURRMODEM" "$ATCMDD")
			#sleep 10
		fi
	;;
	"1199" )
		MODT="0"
		M1='AT!ENTERCND="A710"'
		if [ -z $mask64 ]; then
			mask64="0"
		fi
		flg="0"
		case $uPid in

			"68c0"|"9041"|"901f" ) # MC7354 EM/MC7355
				M2="AT!BAND=11,\"Test\",0,$mask64,0"
			;;
			"9070"|"9071"|"9078"|"9079"|"907a"|"907b" ) # EM/MC7455
				M2='AT!BAND=11,"Test",0,'$mask64,0
				if [ -e /etc/fake ]; then
					M2='AT!BAND=11,"Test",0,'$mask64','$maskl2',0,0,0'
				fi
			;;
			"9090"|"9091"|"90b1" )
				M2='AT!BAND=11,"Test",0,'$mask64','$maskl2',0,0,0'
			;;
			"90d2"|"90d3" )
				OX=$($ROOTER/gcom/gcom-locked "$COMMPORT" "run-at.gcom" "$CURRMODEM" "$M1")
				log "$OX"
				m64=${maskxx:0:64}
				m32=${maskxx:64}
				encode $m64
				m64="0000000000000000"$maskz
				m64=${m64: -16}
				encode $m32
				m32="0000000000000000"$maskz
				m32=${m32: -16}
				M2="AT!BAND=11,1,\"Test\",1,$m64,$m32"
				OX=$($ROOTER/gcom/gcom-locked "$COMMPORT" "run-at.gcom" "$CURRMODEM" "$M2")
				log "$OX"
				m64=${mask5gxx:0:64}
				m32=${mask5gxx:64}
				encode $m64
				m64="0000000000000000"$maskz
				m64=${m64: -16}
				encode $m32
				m32="0000000000000000"$maskz
				m32=${m32: -16}
				M2="AT!BAND=11,1,\"Test\",3,$m64,$m32"
				OX=$($ROOTER/gcom/gcom-locked "$COMMPORT" "run-at.gcom" "$CURRMODEM" "$M2")
				log "$OX"
				m64=${mask5gsaxx:0:64}
				m32=${mask5gsaxx:64}
				encode $m64
				m64="0000000000000000"$maskz
				m64=${m64: -16}
				encode $m32
				m32="0000000000000000"$maskz
				m32=${m32: -16}
				M2="AT!BAND=11,1,\"Test\",4,$m64,$m32"
				OX=$($ROOTER/gcom/gcom-locked "$COMMPORT" "run-at.gcom" "$CURRMODEM" "$M2")
				log "$OX"
				flg="1"
			;;
			
		esac
		log "$M2"
		if [ -e /etc/fake ]; then
			exit 0
		fi
		if [ "$flg" = "0" ]; then
			OX=$($ROOTER/gcom/gcom-locked "$COMMPORT" "run-at.gcom" "$CURRMODEM" "$M1")
			log "$OX"
			OX=$($ROOTER/gcom/gcom-locked "$COMMPORT" "run-at.gcom" "$CURRMODEM" "$M2")
			log "$OX"
		fi
		M2='AT!BAND=00;!BAND=11'
		OX=$($ROOTER/gcom/gcom-locked "$COMMPORT" "run-at.gcom" "$CURRMODEM" "$M2")
		log "$OX"
		if [ $RESTART = "1" ]; then
			ATCMDD="AT+CFUN=1,1"
			OX=$($ROOTER/gcom/gcom-locked "$COMMPORT" "run-at.gcom" "$CURRMODEM" "$ATCMDD")
			ATCMDD='AT!ENTERCND="AWRONG"'
		fi
		OX=$($ROOTER/gcom/gcom-locked "/dev/ttyUSB$CPORT" "run-at.gcom" "$CURRMODEM" "$ATCMDD")
	;;
	"8087"|"2cb7"|"0e8d" )
		MODT="2"
		FM150=""
		if [ $uVid = 2cb7 ]; then
			FM150=$(echo $model | grep "FM150")
			if [ -z $FM150 ]; then
				COMM="XACT"
			else
				COMM="GTACT"
			fi
		else
			COMM="XACT"
		fi
		if [ $uVid = 0e8d ]; then
			COMM="GTACT"
		fi

		lte=""
		if [ ! -z $mask ]; then
			fibdecode $mask 1 0
			lte=","$lst
		fi
		L1="4,2,1"
		lst=""
		if [ -n "$FM150" ]; then
			if [ -n "$lte" ]; then
				L1="17,6,"
			else
				L1="14,,"
			fi
			if [ -n "$mask5g" ]; then
				fibdecode $mask5g 5 0
				lst=","$lst
			else
				L1="4,3,"
			fi
		fi
		if [ $uVid = 0e8d ]; then
			L1="17,3,6"
			if [ ! -z $mask5g ]; then
				fibdecode $mask5g 5 0
				lst=","$lst
			else
				L1="4,3,3"
			fi
		fi
		ATCMDD="AT+""$COMM"="$L1$lte$lst"
		log " "
		log "Lock Command : $ATCMDD"
		log " "

		#exit 0

		OX=$($ROOTER/gcom/gcom-locked "/dev/ttyUSB$CPORT" "run-at.gcom" "$CURRMODEM" "$ATCMDD")
		log " "
		log "Lock Response : $OX"
		log " "
		if [ $RESTART = "1" ]; then
			ATCMDD="AT+CFUN=1,1"
			OX=$($ROOTER/gcom/gcom-locked "/dev/ttyUSB$CPORT" "run-at.gcom" "$CURRMODEM" "$ATCMDD")
		fi
	;;
	"413c" )
		MODT="3"
		case $uPid in

			"81d7"|"81d8"|"e0b4" |"e0b5"|"1910")
				if [ ! -z $mask ]; then
					fibdecode $mask 1 2
					ATCMDD="AT^SLBAND=LTE,2,""$lst"
					log "$ATCMDD"
				else
					exit 0
				fi
				OX=$($ROOTER/gcom/gcom-locked "/dev/ttyUSB$CPORT" "run-at.gcom" "$CURRMODEM" "$ATCMDD")
				log " "
				log "Lock Response : $OX"
				log " "
				if [ $RESTART = "1" ]; then
					ATCMDD="AT+CFUN=1,1"
					OX=$($ROOTER/gcom/gcom-locked "/dev/ttyUSB$CPORT" "run-at.gcom" "$CURRMODEM" "$ATCMDD")
				fi
			;;
			"81df")
				if [ ! -z $mask ]; then
					ATCMDD="AT^BAND_PREF"
					OX=$($ROOTER/gcom/gcom-locked "/dev/ttyUSB$CPORT" "run-at.gcom" "$CURRMODEM" "$ATCMDD")
					fibdecode $mask 1 2
					bnds="$lst"",0"
					enc=$(echo "$bnds" | grep -o "," | wc -l)
					if [ "$enc" -lt 30 ]; then
						if [ "$enc" -gt 15 ]; then
							dis=''
							for i in 1 2 3 4 5 7 8 12 13 14 17 18 19 20 25 26 28 29 30 32 34 38 39 40 41 42 46 48 66 71
							do
							   j=1
								while [ 1=1 ]; do
									bn=$(echo $bnds | cut -d, -f$j)
									if [ "$bn" = "0" -o "$bn" -gt "$i" ]; then
										if [ -z "$dis" ]; then
											dis=$i
										else
											dis=$dis","$i
										fi
										break
									fi
									if [ "$bn" = "$i" ]; then
										break
									fi
									let j=$j+1
								done
							done
							lst="1,"$dis
						else
							lst="2,"$lst
						fi
						ATCMDD="AT^BAND_PREF=LTE,""$lst"
						log "$ATCMDD"
						OX=$($ROOTER/gcom/gcom-locked "/dev/ttyUSB$CPORT" "run-at.gcom" "$CURRMODEM" "$ATCMDD")
						log " "
						log "Lock Response : $OX"
						log " "
					fi
				else
					exit 0
				fi
				
				if [ ! -z "$mask5g" ]; then
					fibdecode $mask5g 1 2
					bnds="$lst"",0"
					enc=$(echo "$bnds" | grep -o "," | wc -l)
					mw=$(uci -q get modem.modem$CURRMODEM.mw)
					if [ "$mw" = "1" ]; then
						if [ "$enc" -lt 20 ]; then
							if [ "$enc" -gt 15 ]; then
								dis=''
								for i in 1 2 3 5 7 8 12 20 28 38 41 66 71 77 78 79 257 258 260 261
								do
								   j=1
									while [ 1=1 ]; do
										bn=$(echo $bnds | cut -d, -f$j)
										if [ "$bn" = "0" -o "$bn" -gt "$i" ]; then
											if [ -z "$dis" ]; then
												dis=$i
											else
												dis=$dis","$i
											fi
											break
										fi
										if [ "$bn" = "$i" ]; then
											break
										fi
										let j=$j+1
									done
								done
								lst="1,"$dis
							else
								lst="2,"$lst
							fi
							ATCMDD="AT^BAND_PREF=NR5G,""$lst"
							log "$ATCMDD"
							OX=$($ROOTER/gcom/gcom-locked "/dev/ttyUSB$CPORT" "run-at.gcom" "$CURRMODEM" "$ATCMDD")
							log " "
							log "Lock Response : $OX"
							log " "
						fi
					else
						if [ "$enc" -lt 16 ]; then
							if [ "$enc" -gt 15 ]; then
								dis=''
								for i in 1 2 3 5 7 8 12 20 28 38 41 66 71 77 78 79
								do
								   j=1
									while [ 1=1 ]; do
										bn=$(echo $bnds | cut -d, -f$j)
										if [ "$bn" = "0" -o "$bn" -gt "$i" ]; then
											if [ -z "$dis" ]; then
												dis=$i
											else
												dis=$dis","$i
											fi
											break
										fi
										if [ "$bn" = "$i" ]; then
											break
										fi
										let j=$j+1
									done
								done
								lst="1,"$dis
							else
								lst="2,"$lst
							fi
							ATCMDD="AT^BAND_PREF=NR5G,""$lst"
							log "$ATCMDD"
							OX=$($ROOTER/gcom/gcom-locked "/dev/ttyUSB$CPORT" "run-at.gcom" "$CURRMODEM" "$ATCMDD")
							log " "
							log "Lock Response : $OX"
							log " "
						fi
					fi
				fi
				/usr/lib/rooter/connect/bandmask $CURRMODEM $MODT
				exit 0
			;;
		esac
	;;
	* )
		exit 0
	;;
esac

if [ $RESTART = "0" ]; then
	/usr/lib/rooter/connect/bandmask $CURRMODEM $MODT
	exit 0
fi
rm -f /tmp/bmask
if [ $3 = "12" ]; then
	/usr/lib/rooter/luci/restart.sh $CURRMODEM 11
else
	/usr/lib/rooter/luci/restart.sh $CURRMODEM 11
fi
sleep 10
#/usr/lib/rooter/connect/bandmask $CURRMODEM $MODT
exit 0
