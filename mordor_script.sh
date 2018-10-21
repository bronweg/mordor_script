#!/bin/bash

grub() {		# Update GRUB. Enforce deadline scheduler argument
echo "GRUB will be updated with elevator=deadline argument"
grubby --args="elevator=deadline" --update-kernel $(grubby --default-kernel)
if [[ $? -eq 0 ]]; then
	echo "GRUB has been updated"
else
	echo "ERROR! GRUB hasn't been updated"
fi
grubby --info $(grubby --default-kernel)
}

prepare_ext4() {		# Adding hdfs declaration to [fs_types] section
echo "Adding hdfs declaration to [fs_types] section of /etc/mke2fs.conf file"
if [[ -z $(grep "hdfs = {" /etc/mke2fs.conf) ]]; then
	sed -i.bak.$(date +%Y%m%d%H%M) 's/^\[fs_types\]/\[fs_types\]\n\thdfs = \{\n\t\tfeatures = has_journal,extent,huge_file,flex_bg,uninit_bg,dir_nlink,extra_isize\n\t\tinode_ratio = 131072\n\t\tblocksize = -1\n\t\treserved_ratio = 0\n\t\tdefault_mntopts = acl,user_xattr\n\t\}/g' /etc/mke2fs.conf
	if [[ $? -eq 0 ]]; then
  	      echo "Hdfs declaration has been added"
	else
	        echo "ERROR! Hdfs declaration hasn't been added"
	fi
else
	echo "hdfs declaraion already present in /etc/mke2fs.conf file. No changes needed."
fi
}

make_ext4() {		# Making ext4 file system
echo "Making ext4 file system on all disks except of OS disk"
exit_status=0
for disk in ${disks_to_create_fs}; do mke2fs -F -t ext4 -L ${disk_label} ${mkfs_param} /dev/${disk}; exit_status=$(expr $exit_status + $?); done
if [[ $exit_status -eq 0 ]]; then
	echo -e "New file systems created on below list of disks\n${disks_to_create_fs}"
else
	echo -e "ERROR! At least one file system hasn't been created on below list of disks\n${disks_to_create_fs}"
fi
}

mount_fs() {		# Updating /etc/fstab file, creating mount point directories in /data/ folder, mounting data file systems.
counter=0
#last_mnt=1
disk_num=0

for disk in ${disks_to_create_fs}; do
	if [[ $(amount=$(basename ${mntpnt_prfx[${counter}]}_amount) && echo ${!amount}) ]]; then
		amount=$(basename ${mntpnt_prfx[${counter}]}_amount)
		prefix=${mntpnt_prfx[${counter}]}
		disk_num=$(expr $disk_num + 1)
		if [[ ${disk_num} -lt ${!amount} ]]; then :; else counter=$(expr $counter + 1); fi
	else
		if [[ ${mntpnt_prfx[${counter}]} ]]; then
			prefix=${mntpnt_prfx[${counter}]}
			disk_num=1
		else
			#prefix=$(echo ${mntpnt_prfx[@]} | awk '{print $NF}')
			prefix=${mntpnt_prfx[-1]}
			#last=true
			disk_num=$(expr $disk_num + 1)
		fi
		counter=$(expr $counter + 1)
	fi
	
	#counter=$(expr $counter + 1)
	disk_num=$(printf %02d $disk_num)
	#counter=$(printf %02d $counter)
	if [[ -z $(grep -w "/dev/${disk}" /etc/fstab) ]]; then
		echo "/dev/${disk} mountpoint will be mounted to ${prefix}${disk_num} folder"
		echo -e "/dev/${disk}\t${prefix}${disk_num}\text4\t${mnt_opts}\t1 1" >> /etc/fstab
	elif [[ -z $(grep "/dev/${disk}[[:space:]]${prefix}${disk_num}[[:space:]]ext4[[:space:]]${mnt_opts}[[:space:]]1 1" /etc/fstab) ]]; then
		echo "WARNING! /dev/${disk} is already present in /etc/fstab but is wrong and will be changed."
		sed -i.bak.$(date +%Y%m%d%H%M) "s|$(grep -w "/dev/${disk}" /etc/fstab)|\
			$(echo -e "/dev/${disk}\t${prefix}${disk_num}\text4\t${mnt_opts}\t1 1")|g" /etc/fstab
	fi
	if [[ $? -eq 0 ]]; then echo "/etc/fstab file has been updated"; else echo "ERROR! /etc/fstab file hasn't been updated."; fi
	mkdir -p ${prefix}${disk_num}
	if [[ $? -eq 0 ]]; then echo "Folder has been created"; else echo "ERROR! Folder hasn't been created."; fi
done
mount -a
if [[ $? -eq 0 ]]; then echo "All relevant mountpoints have been mounted"; else echo "ERROR! Not all relevant mountpoints have been mounted"; fi
}

disk_operations() {
unset mkfs_param
case $1 in
	--dn)
		role="dn"
		disk_label="HDFS"
		mkfs_param="-T hdfs"
		mntpnt_prfx=("/data/dn")
		mnt_opts="defaults,inode_readahead_blks=128,data=writeback,noatime,nodev,nobarrier"
		prepare_ext4
		;;
	--kudu)
		role="dn"
		disk_label="HDFS"
		mkfs_param="-T hdfs"
		mntpnt_prfx=("/data/kudu" "/data/dn")
		mnt_opts="defaults,inode_readahead_blks=128,data=writeback,noatime,nodev,nobarrier"
		kudu_amount=$2
		prepare_ext4
		;;
	--db)
		role="master"
                disk_label="GRID"
		mntpnt_prfx=("/data/db")
                mnt_opts="defaults,noatime,nodev,nobarrier"
		;;
	--utility)
		role="master"
                disk_label="GRID"
		mntpnt_prfx=("/data/logs")
                mnt_opts="defaults,noatime,nodev,nobarrier"
		;;
	--master) #Include ambari node
		role="master"
		disk_label="GRID"
		mntpnt_prfx=("/data/logs" "/data/zk" "/data/jn" "/data/nn")
		mnt_opts="defaults,noatime,nodev,nobarrier"
		;;
	--kafka)
		role="kafka"
		disk_label="GRID"
		mntpnt_prfx=("/data/kafka")
		mnt_opts="defaults,noatime,nodev,nobarrier"
		;;
	--edge) #Include KMS and KNOX nodes
		role="edge"
		disk_label="GRID"
		mntpnt_prfx=("/data/data")
		mnt_opts="defaults,noatime,nodev,nobarrier"
		;;
	*)
		echo "ERROR! You should provide argument [ --dn | --kudu {NUM of disks} | --db | --utility | --master | --kafka | --edge ] to $0 function. Exiting"
		exit 1
		;;
esac
#disks_to_work_on=$(bootvg=$(df | grep -w \/boot$ | awk '{print $1}') && bootvg=${bootvg##/dev/} && lsblk | grep ^sd[a-z] | grep -v ${bootvg%%[0-9]} | awk '{print $1}')
#disks_to_work_on=$(bootvg=$(df | grep -w \/$ | awk '{print $1}') && bootvg=${bootvg##/dev/} && lsblk | grep ^${bootvg%%[a-z][0-9]*} | grep -v ${bootvg%%[0-9]*} | awk '{print $1}')
bootvg=$(lsblk -i | awk -v LVDEV=$(basename $(df / | grep / | awk '{print $1}')) '$1 ~ /^[^|`]/ {LASTDEV=$1} index($1, LVDEV) > 0 {print LASTDEV}')
#disks_to_work_on=$(lsblk | grep ^${bootvg%%[a-z][0-9]*} | grep -v ${bootvg%%[0-9]*} | awk '{print $1}')
disks_to_work_on=$(lsblk | grep ^${bootvg%%[a-z]} | grep -v ${bootvg%%[0-9]*} | awk '{print $1}')
#disks_to_create_fs=$(lsblk -f | egrep $(echo $disks_to_work_on | sed "s/ /|/g") | awk -v disk_label="$disk_label" '$3 != disk_label {print $1}')
disks_to_create_fs=$(lsblk -b -o NAME,LABEL,SIZE | tail -n +2 | awk '{print $NF"\t"$0}' | egrep $(echo $disks_to_work_on | sed "s/ /|/g") | sort -k 1.1nr -k 2.1 | awk -v disk_label="$disk_label" '$3 != disk_label {print $2}')
make_ext4
mount_fs
}

block_device_optimization() {		# Block Device Optimization
echo "Block Device Optimization. /etc/rc.local file will be also updated."
for disk in $hdfs_disks; do
	echo 512 > /sys/block/${disk}/queue/nr_requests
	echo 254 > /sys/block/${disk}/device/queue_depth
	/sbin/blockdev --setra 1024 /dev/${disk}
	echo "echo 512 > /sys/block/${disk}/queue/nr_requests" >> /etc/rc.local
	echo "echo 254 > /sys/block/${disk}/device/queue_depth" >> /etc/rc.local
	echo "/sbin/blockdev --setra 1024 /dev/${disk}" >> /etc/rc.local
done
}

tso_config() {		# NIC Configuration
echo "NIC Configuration. The TSO configuration will be turned on"
if [[ $(ethtool -k $(ip route show | grep default | grep -oiw "dev [a-z]*[0-9]" | awk '{print $2}') | grep tcp-.*segmentation | awk '{print $NF}' | sort -u) == "on" ]]; then
	echo "Everything is ok. TSO is turned on"
else
	echo "WARNING! TSO is turned off"
	echo "Trying to turn it on"
	ethtool -K $(ip route show | grep default | grep -oiw "dev [a-z]*[0-9]" | awk '{print $2}') tso on
	if [[ $(ethtool -k $(ip route show | grep default | grep -oiw "dev [a-z]*[0-9]" | awk '{print $2}') | grep tcp-.*segmentation | awk '{print $NF}' | sort -u) == "on" ]]; then
		echo "Everything is ok. TSO has been turned on"
	else
		echo "ERROR! can't turn on TSO. Please do it manualy."
	fi
fi
}

fix_conf() {		#Got 4 argument and changing config files
key=$1; delimiter=$2; value=$3; file=$4
if [[ $# -ne 4 ]]; then
	echo "ERROR! You should provide 4 arguments to $0 func. Exiting." && return 1
else
	echo -e "The \"${key}${delimiter}${value}\" will be checked and updated/appended if needed in ${file} file"
fi
if ( [[ ! -e ${file} ]] && [[ -w $(dirname ${file}) ]] ) || ( [[ -z $(grep -w "${key}" ${file}) ]] && [[ -w ${file} ]] ); then
	echo "updating..."
	echo "${key}${delimiter}${value}" >> ${file}
elif [[ -z $(grep "${key}${delimiter}${value}" ${file}) ]]; then
	echo "updating..."
	sed -i.bak "s|${key}.*|${key}${delimiter}${value}|g" ${file}
elif [[ ! -w ${file} ]] || [[ ! -w $(dirname ${file}) ]]; then
	echo "ERROR! There is no write permissions on ${file} file or on $(dirname ${file}) folder for $(whoami) user." && return 1
else
	echo "The parameter ${key} already has the correct value ${value} in ${file} file"
fi
}

os_tuning() {		#Changing conf files by fix_conf function for OS tuning
file=/etc/limits
delimiter=" "
fix_conf '* - nofile' "$delimiter" 32768 $file
fix_conf '* - nproc' "$delimiter" 65536 $file
file=/etc/sysctl.conf
delimiter=" = "
fix_conf net.core.netdev_max_backlog "$delimiter" 4000 $file
fix_conf net.core.somaxconn "$delimiter" 4000 $file
fix_conf net.ipv4.ip_forward "$delimiter" 0 $file
fix_conf net.ipv4.conf.default.rp_filter "$delimiter" 1 $file
fix_conf net.ipv4.conf.default.accept_source_route "$delimiter" 0 $file
fix_conf net.ipv4.tcp_syncookies "$delimiter" 1 $file
fix_conf net.ipv4.tcp_sack "$delimiter" 0 $file
fix_conf net.ipv4.tcp_dsack "$delimiter" 0 $file
fix_conf net.ipv4.tcp_keepalive_time "$delimiter" 600 $file
fix_conf net.ipv4.tcp_keepalive_probes "$delimiter" 5 $file
fix_conf net.ipv4.tcp_keepalive_intvl "$delimiter" 15 $file
fix_conf net.ipv4.tcp_fin_timeout "$delimiter" 30 $file
fix_conf net.ipv4.tcp_rmem "$delimiter" "32768 436600 4193404" $file
fix_conf net.ipv4.tcp_wmem "$delimiter" "32768 436600 4193404" $file
fix_conf net.ipv4.tcp_retries2 "$delimiter" 10 $file
fix_conf net.ipv4.tcp_synack_retries "$delimiter" 3 $file

fix_conf net.ipv6.conf.all.disable_ipv6 "$delimiter" 1 $file
fix_conf net.ipv6.conf.default.disable_ipv6 "$delimiter" 1 $file
fix_conf net.ipv6.conf.lo.disable_ipv6 "$delimiter" 1 $file

fix_conf kernel.sysrq "$delimiter" 0 $file
fix_conf kernel.core_uses_pid "$delimiter" 1 $file
fix_conf kernel.msgmnb "$delimiter" 65536 $file
fix_conf kernel.msgmax "$delimiter" 65536 $file
fix_conf kernel.shmmax "$delimiter" 68719476736 $file
fix_conf kernel.shmall "$delimiter" 4294967296 $file

fix_conf vm.swappiness "$delimiter" 1 $file
sysctl -p	#Reload the parameters on the fly
}

transparent_huge_page() {           # Disable Transparent HugePages
echo "Disable Transparent HugePages. /etc/rc.local file will be also updated."
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag
echo "echo never > /sys/kernel/mm/transparent_hugepage/enabled" >> /etc/rc.local
echo "echo never > /sys/kernel/mm/transparent_hugepage/defrag" >> /etc/rc.local
}

#check_ntp() {
#if [[ -z $(ntpstat | grep synchronised) ]]; then
#	echo "ERROR! NTP isn't synchronised"
#	echo "Please fix the NTP connection manually"
#else
#	echo "NTP check successfully passed."
#fi
#}

check_ntp() {
if [[ -n $(ntpq -np 2> /dev/null | grep '^\*') ]]; then
	echo "ntpd service successfully synchronized to $(ntpq -np | grep '^\*' | awk '{print $1}' | tr -d \*)"
elif [[ $(chronyc sources 2> /dev/null | grep '^.\*') ]]; then
	echo "chrony service successfully synchronized to $(chronyc sources | grep '^.\*' | awk '{print $2}')"
else
	echo "ERROR! NTP isn't synchronised (neither ntpd nor chrony)"
	echo "Please fix the NTP connection manually"
fi
}

help_func() {
echo -e "\nThis script will check and fix nodes environment according to 'Mordor' document of HortonWorks"
echo -e "Author:\t\tUlis Ilya (ulis.ilya@gmail.com)\nCorrector:\tAlex Neishtoot (alexne@matrixbi.co.il)"
echo -e "\n$0 [--help|--dn|--master|--db|--ambari|--edge|--kudu {NUM of disks}|--kms|--knox|--kafka|--all|--manual {list of functions delimited by space}]"
}

declare_nodes() {		#Experimental function, please don't use it.
ambari=(shzambari01)
masters=(shzmst01 shzmst02 shzmst03)
workers=(shzdn01 shzdn02 shzdn03 shzdn04 shzdn05)
edges=(shzedge01)
kms=(shzkms01)
kafka=(shzkafka01)
knox=(shzknox01)
airflow=(shzaff01)
all_nodes=(${ambari[@]} ${masters[@]} ${workers[@]} ${edges[@]} ${kms[@]} ${kafka[@]} ${knox[@]} ${airflow[@]})
}

script_arguments() {
while [[ $# -gt 0 ]]; do
	case $1 in
		--dn)
			echo "The script will run data node functions"
			shift
			grub
			#prepare_ext4
			#make_ext4
			#mount_hdfs
			disk_operations --dn
			block_device_optimization
			tso_config
			os_tuning
			transparent_huge_page
			check_ntp
			;;
		--master)
			echo "The script will run master functions"
			shift
			grub
			disk_operations --master
			tso_config
			os_tuning
			transparent_huge_page
			check_ntp
			;;
		--db)
			echo "The script will run ambari functions"
			shift
			grub
			disk_operations --db
            		tso_config
            		os_tuning
            		transparent_huge_page
            		check_ntp
			;;
		--ambari)
			echo "The script will run ambari functions"
			shift
			grub
			disk_operations --utility
            		tso_config
            		os_tuning
            		transparent_huge_page
            		check_ntp
			;;
		--edge)
			echo "The script will run edge functions"
			shift
			grub
			disk_operations --edge
            		tso_config
            		os_tuning
            		transparent_huge_page
            		check_ntp
			;;
		--kudu)
			echo "The script will run kudu functions"
			shift
			alike_num='^[1-9][0-9]*$'
			if [[ $1 =~ ${alike_num} ]]; then
				disk_operations --kudu $1
				shift
			else
				echo "ERROR! You should provide amount of disks to create to '--kudu' argument."
				exit 1
			fi
			grub
			block_device_optimization
			tso_config
			os_tuning
			transparent_huge_page
			check_ntp
			;;
		--kms)
			echo "The script will run kms functions"
			shift
			grub
			disk_operations --edge
            		tso_config
           		os_tuning
          		transparent_huge_page
         		check_ntp
			;;
		--knox)
			echo "The script will run knox functions"
			shift
			grub
			disk_operations --edge
            		tso_config
            		os_tuning
            		transparent_huge_page
            		check_ntp
			;;
		--kafka)
			echo "The script will run kafka functions"
			shift
			grub
            		disk_operations --kafka
            		tso_config
            		os_tuning
            		transparent_huge_page
            		check_ntp
			;;
		--all)
			echo "The script will run all functions"
			shift
			grub
			tso_config
            		os_tuning
			transparent_huge_page
			check_ntp
			;;
		--manual)
			shift
			counter=0
			while [[ -n $1 ]]; do
				(( counter++ ))
				if [[ $1 == "disk_operations" ]]; then
					if [[ $2 == "--kudu" ]]; then
					        func[${counter}]="$1 $2 $3"
						shift
						shift
						shift
					else
						func[${counter}]="$1 $2"
						shift
						shift
					fi
				else
					func[${counter}]=$1
					shift
				fi
			done
			echo -e "The following functions will run:\n${func[@]}"
			for function in "${func[@]}"; do
				$function
			done
			;;
		--help)
			help_func
			exit 0
			;;
		*)
			echo "ERROR! Wrong argument."
			help_func
			exit 1
	esac
done
}

script_arguments $@

#EOF
