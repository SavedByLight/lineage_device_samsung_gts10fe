#!/vendor/bin/sh
# $1 = trigger cause (from kernel->wlbtd)
# $2 = 16-bit hex reason code
# $3 = enable to create tar file with sable (1: enable, 0: disable)
# $4 = enable to create moredump file (1: enable, 0: disable)

THIS_SCRIPT_VERSION="2.1"
# Version 2.0 : extract scsc_log_common_xxx.tar.gz to reduce log size. No moreduemp and mx_dump.
# Version 2.1 : WLBTD can selectively create sables and moredumps.

dir="`cat /sys/module/scsc_log_collection/parameters/collection_target_directory`"
max_logs="`getprop vendor.wlbtd.tar_files_per_trigger`"
wlbtd_version="`getprop vendor.wlbtd.version`"
DATE_TAG="`date +%Y_%m_%d__%H_%M_%S`"
moredumpdir=/data/vendor/log/wifi
memdump_file=/sys/wifi/memdump

base_dir=`cat /sys/module/scsc_mx/parameters/base_dir`
fw_var=`cat /sys/module/scsc_mx/parameters/firmware_variant`
fw_suffix=`cat /sys/module/scsc_mx/parameters/firmware_hw_ver`
xml_dir=$base_dir/$fw_var$fw_suffix/debug/hardware/moredump
log_strings=$base_dir/$fw_var$fw_suffix/debug/common/log-strings.bin

take_moredump()
{
memdump_file_val=1
if [ -f ${memdump_file} ]; then
	memdump_file_val=`cat $(eval echo ${memdump_file})`
	echo "$(eval echo ${memdump_file}) : ${memdump_file_val}"  >> ${status_file} 2>&1
fi

if [[ ${memdump_file_val} != "0" ]]; then
	echo "Collecting Moredump" >> ${status_file}
	start=`date +%s`
	if grep -q -E -i "lassen|leman|nacho|neus|orange" /proc/driver/mxman_info/mx_release; then
		moredump.bin ${moredumpdir}/moredump_${DATE_TAG}.cmm -xml_path ${xml_dir} -log_strings ${log_strings} 2>>${status_file} >/dev/null
	else
		# p-series chip log_strings are in the FW image
		moredump.bin ${moredumpdir}/moredump_${DATE_TAG}.cmm -xml_path ${xml_dir} -firmware_binary ${base_dir}/${fw_var}${fw_suffix}.bin 2>>${status_file} >/dev/null
	fi
	script_status=$?
	echo "Generated moredump moredump_${DATE_TAG}.cmm|moredump_${DATE_TAG}.err.cmm" >>${status_file}
	end=`date +%s`
	echo "moredump generated in ${moredumpdir} in $((end-start)) seconds" >> ${status_file} 2>&1
	if [ -f ${moredumpdir}/moredump_${DATE_TAG}.cmm ]; then
		chmod 755 ${moredumpdir}/moredump_${DATE_TAG}.cmm
		cp -a ${moredumpdir}/moredump_${DATE_TAG}.cmm ${logdir}
		if [ $? -eq 0 ]; then
			echo "copied ${moredumpdir}/moredump_${DATE_TAG}.cmm to ${logdir}" >> ${status_file} 2>&1
		else
			echo "copy failed($?) ${moredumpdir}/moredump_${DATE_TAG}.cmm is not copied." >> ${status_file} 2>&1
		fi
	elif [ -f ${moredumpdir}/moredump_${DATE_TAG}.err.cmm ]; then
		chmod 755 ${moredumpdir}/moredump_${DATE_TAG}.err.cmm
		cp -a ${moredumpdir}/moredump_${DATE_TAG}.err.cmm ${logdir}
		if [ $? -eq 0 ]; then
			echo "copied ${moredumpdir}/moredump_${DATE_TAG}.err.cmm to ${logdir}" >> ${status_file} 2>&1
		else
			echo "copy failed($?) ${moredumpdir}/moredump_${DATE_TAG}.err.cmm is not copied." >> ${status_file} 2>&1
		fi
	else
		echo "Cannot find moredump_${DATE_TAG}.cmm or moredump_${DATE_TAG}.err.cmm in ${moredumpdir}" >> ${status_file}
	fi
	sync
fi
}

logcat_dmesg_logs()
{
SAMLOG=/sys/kernel/debug/scsc/ring0/samlog
MXDECO=/vendor/bin/mxdecoder

#If it use devfs instead of debugfs
if [ ! -e ${SAMLOG} ]; then
	SAMLOG=/dev/samlog
fi

# dump dmesg
echo "collecting kernel log using dmesg" >> ${status_file}
dmesg > ${logdir}/dmesg_${DATE_TAG}.log 2>>${status_file} #print errors to status file
echo "generated ${logdir}/dmesg_${DATE_TAG}.log" >> ${status_file} 2>&1

# dump logring
if [ -e ${SAMLOG} ]; then
	cat /proc/driver/mxman_info/mx_release > ${logdir}/mx.dump_${DATE_TAG}.log 2>&1
	echo "collecting mx dump from ${SAMLOG}" >> ${status_file}
	if [ ! -e ${MXDECO} ]
	then
		echo "No mxdecoder found...dumping RAW logring." >> ${logdir}/mx.dump_${DATE_TAG}.log
		cat ${SAMLOG} >> ${logdir}/mx.dump_${DATE_TAG}.log 2>>${status_file} #print errors to status file
	else
		cat ${SAMLOG} | $MXDECO >> ${logdir}/mx.dump_${DATE_TAG}.log 2>>${status_file} #print errors to status file
	fi
	echo "generated ${logdir}/mx.dump_${DATE_TAG}.log" >> ${status_file} 2>&1
fi
}

remove_old_tar_and_cmm_files()
{
# if vendor.wlbtd.tar_files_per_trigger property is not set, hardcode value 5
# otherwise we will not delete any old files and keep filling the storage with tar files
if [[ ${max_logs} == " " ]]; then
	max_logs=5
fi

cd ${dir}
if [ ${max_logs} -eq 0 ]; then
	# only keep the last tar and cmm file
	count="`ls -tr ${tarext} | wc -l`"
	while [ ${count} -gt 1 ]
	do
		oldest="`ls -tr ${tarext} | head -n 1`"
		echo "removed ${oldest}" >> ${status_file} 2>&1
		rm -f ${oldest} > /dev/null 2>&1
                ((count=count - 1))
	done

        cmmcount="`ls -tr moredump* | wc -l`"
        while [ ${cmmcount} -gt 1 ]
        do
                oldestcmm="`ls -tr moredump* | head -n 1`"
                echo "removed ${oldestcmm}" >> ${status_file} 2>&1
                rm -f ${oldestcmm} > /dev/null 2>&1
                ((cmmcount=cmmcount-1))
        done

        dumpcount="`ls -tr SCAN2MEM* | wc -l`"
        while [ ${dumpcount} -gt 1 ]
        do
                oldestdump="`ls -tr SCAN2MEM* | head -n 1`"
                echo "removed ${oldestdump}" >> ${status_file} 2>&1
                rm -f ${oldestdump} > /dev/null 2>&1
                ((dumpcount=dumpcount-1))
        done
else
	# remove old tar files of each type
	list_of_triggers="scsc_log_dumpstate_wlbt_off  \
		scsc_log_user scsc_log_fw \
		scsc_log_dumpstate scsc_log_host_wlan \
		scsc_log_host_bt scsc_log_host_common \
		scsc_log_fw_panic scsc_log_sys_error \
		scsc_log_common"
	for i in ${list_of_triggers}
	do
		count="`ls -tr ${i}${tarext} | wc -l`"

		while [ ${count} -gt ${max_logs} ]
		do
			oldest="`ls -tr ${i}${tarext} | head -n 1`"
			echo "removed ${oldest}" >> ${status_file} 2>&1
			rm -f ${oldest} > /dev/null 2>&1
                        ((count=count-1))
		done
	done

        cmmcount="`ls -tr moredump* | wc -l`"
        while [ ${cmmcount} -gt ${max_logs} ]
        do
                oldestcmm="`ls -tr moredump* | head -n 1`"
                echo "removed ${oldestcmm}" >> ${status_file} 2>&1
                rm -f ${oldestcmm} > /dev/null 2>&1
                ((cmmcount=cmmcount-1))
        done

        dumpcount="`ls -tr SCAN2MEM* | wc -l`"
        while [ ${dumpcount} -gt 1 ]
        do
                oldestdump="`ls -tr SCAN2MEM* | head -n 1`"
                echo "removed ${oldestdump}" >> ${status_file} 2>&1
                rm -f ${oldestdump} > /dev/null 2>&1
                ((dumpcount=dumpcount-1))
        done
fi
}

#----------------------------------------------------------------------------------------

# if the first command is "last_panic", the script will return the
# last fw panic collected
if [[ $1 ==  last_panic ]]; then
    last_string=`ls $moredumpdir/*panic* -rtd 2>/dev/null| tail -n 1`
    echo $last_string
    exit 0
fi

trigger=$1
code=$2
sable=1
moredump=1
common_trigger="scsc_log_common"

# create .tmp hidden dir
tarfile=${trigger}_${DATE_TAG}_${code}
logdir=${dir}/.tmp-${tarfile}/${tarfile}

common_tarfile=${common_trigger}_${DATE_TAG}_${code}
common_logdir=${dir}/.tmp-${tarfile}/${common_tarfile}

# wlbt-off handling
mx_status="`cat /proc/driver/mxman_ctrl0/mx_status`"
if [ "x${trigger}" == "xscsc_log_dumpstate" ] && [ ! -f /proc/driver/mxman_ctrl0/mx_status ]; then
	tarfile=${trigger}_"wlbt_off"_${DATE_TAG}_${code}
	logdir=${dir}/.tmp-${tarfile}/${tarfile}
fi

# remove spurious .tmp folders if present
rmdir -p ${dir}/.tmp-*

# make sure the dir exists
mkdir -p ${logdir}
mkdir -p ${common_logdir}

status_file=${logdir}/status_${DATE_TAG}.log
common_status_file=${common_logdir}/status_${DATE_TAG}.log
temp_release_file=${logdir}/test_rel.txt

# create status file
touch ${status_file}
echo "THIS_SCRIPT_VERSION:${THIS_SCRIPT_VERSION}" > ${status_file} 2>&1
echo "created ${logdir}" >> ${status_file} 2>&1
echo "created ${status_file}" >> ${status_file} 2>&1

MX_RELEASE=$(cat /proc/driver/mxman_info/mx_release)
echo "$MX_RELEASE" >> ${status_file} 2>&1

echo $MX_RELEASE | awk -F'[: .]+' '{print $2, $3, $4, $5, $6}' > ${temp_release_file}
read REL_PRODUCT REL_ITERATION REL_CANDIDATE REL_POINT REL_CUSTOMER < ${temp_release_file}
rm ${temp_release_file}

echo "SCSC Release $REL_PRODUCT.$REL_ITERATION.$REL_CANDIDATE.$REL_POINT.$REL_CUSTOMER" >> ${status_file} 2>&1

if [ $REL_PRODUCT -gt 12 ]; then
	sable=$3
	moredump=$4
	echo "sable: ${sable}, moredump:${moredump} (enable: 1, disable: 0)" >> ${status_file} 2>&1
elif [ $REL_PRODUCT -eq 12 ] && [ $REL_ITERATION -gt 23 ]; then
	sable=$3
	moredump=$4
	echo "sable: ${sable}, moredump:${moredump} (enable: 1, disable: 0)" >> ${status_file} 2>&1
elif [ $REL_PRODUCT -eq 12 ] && [ $REL_ITERATION -eq 23 ] && [ $REL_CANDIDATE -eq 0 ] && [ $REL_POINT -ge 161 ]; then
	sable=$3
	moredump=$4
	echo "[Redwood] Sable: ${sable}, moredump: ${moredump} (enable: 1, disable: 0)" >> ${status_file} 2>&1
else
	echo "All types of dump must be generated in this legacy project." >> ${status_file} 2>&1
fi

cd ${dir}
if [ ${sable} -eq 1 ]; then
#	no .sbl found exit
	if [ -z .tmp-${trigger}.sbl ]; then
		echo ".tmp-${trigger}.sbl not found. exiting." >> ${status_file} 2>&1
		log -t "WLBTD" -p e ".tmp-${trigger}.sbl not found. exiting."
		exit 0
	fi

# 	copy .sbl file
	mv .tmp-${trigger}.sbl ${logdir}/${trigger}_${DATE_TAG}_${code}.sbl 2>&1
	echo "copied .tmp-${trigger}.sbl to ${logdir}/${trigger}_${DATE_TAG}_${code}.sbl" >> ${status_file} 2>&1
	cp -f ${logdir}/${trigger}_${DATE_TAG}_${code}.sbl ${common_logdir}/${common_trigger}_${DATE_TAG}_${code}.sbl 2>&1
else
# 	Skip copying .sbl file
	echo "SABLE Collection is disabled. No .sbl file generated." >> ${status_file} 2>&1
	log -t "WLBTD" -p e "SABLE Collection is disabled. No .sbl file generated."
fi

cd ${logdir}
echo "working dir: `pwd`" >> ${status_file} 2>&1

if [ ${sable} -eq 1 ]; then
	logcat_dmesg_logs
else
# Skip dumping dmesg and logring file
	echo "SABLE Collection is disabled. No dmesg & logring file generated." >> ${status_file} 2>&1
	log -t "WLBTD" -p e "SABLE Collection is disabled. No dmesg & logring file generated."
fi

# take moredump in case of scsc_log_fw_panic
if [ "x${trigger}" == "xscsc_log_fw_panic" ] && [ ${moredump} -eq 1 ]; then
	if [ -f /vendor/bin/moredump.bin ]; then

		take_moredump

		chmod 0666 ${logdir}/dmesg_${DATE_TAG}.log
		chmod 0666 ${logdir}/mx.dump_${DATE_TAG}.log
		echo "ls ${logdir}" >> ${status_file}
		ls -l ${logdir} 2>&1 >> ${status_file}
#		cp -a ${logdir}/dmesg_${DATE_TAG}.log ${moredumpdir}
#		cp -a ${logdir}/mx.dump_${DATE_TAG}.log ${moredumpdir}
	else
		echo "/vendor/bin/moredump.bin not found. No moredump generated." >> ${status_file} 2>&1
		log -t "WLBTD" -p e "/vendor/bin/moredump.bin not found. No moredump generated."
	fi
else
	echo "Triggering moredump is disabled. No moredump generated." >> ${status_file} 2>&1
	log -t "WLBTD" -p e "Triggering moredump is disabled. No moredump generated."
fi

# copy log-strings.bin
if [ ${sable} -eq 1 ]; then
	cp ${log_strings} ${logdir} 2>&1
	echo "copied ${log_strings} ${logdir}" >> ${status_file} 2>&1
else
# Skip copying log-strings.bin
	echo "SABLE Collection is disabled. No log-strings.bin generated." >> ${status_file} 2>&1
	log -t "WLBTD" -p e "SABLE Collection is disabled. No log-strings.bin generated."
fi

echo "getprop vendor.wlbtd.tar_files_per_trigger : ${max_logs}" >> ${status_file} 2>&1
echo "getprop vendor.wlbtd.version : ${wlbtd_version}" >> ${status_file} 2>&1
echo "ro.build.date : `getprop ro.build.date`" >> ${status_file} 2>&1
echo "ro.build.fingerprint : `getprop ro.build.fingerprint`" >> ${status_file} 2>&1

cd .. # very important to change to correct directory

cp ${status_file} ${common_status_file} 2>&1
cp ${logdir}/dmesg_${DATE_TAG}.log ${common_logdir}/dmesg_${DATE_TAG}.log 2>&1

script_status=0

##################
sdcard_dir="/sdcard/log"
logstr=""

if [ ${sable} -eq 1 ]; then
	if [ -f /vendor/bin/gunzip ]; then
		tar -czf ./${tarfile}.tar.gz ${tarfile} > /dev/null 2>&1
		tar -czf ./${common_tarfile}.tar.gz ${common_tarfile} > /dev/null 2>&1
		chmod 0666 ./${tarfile}.tar.gz
		chmod 0666 ./${common_tarfile}.tar.gz

		mkdir -p ${sdcard_dir} > ${logstr}
		cp ${tarfile}.tar.gz ${sdcard_dir}/${tarfile}.tar.gz
		cp ${common_tarfile}.tar.gz ${sdcard_dir}/${common_tarfile}.tar.gz

		mv ${tarfile}.tar.gz ${dir}
		mv ${common_tarfile}.tar.gz ${dir}
		log -t "WLBTD" $(eval echo ${dir}/${tarfile}).tar.gz generated

		# create tar.gz
		tarext="*.tar.gz"
	else
		tar -cf ./${tarfile}.tar ${tarfile} > /dev/null 2>&1
		tar -cf ./${common_tarfile}.tar ${common_tarfile} > /dev/null 2>&1
		chmod 0666 ./${tarfile}.tar
		chmod 0666 ./${common_tarfile}.tar
		mv ${tarfile}.tar ${dir}
		mv ${common_tarfile}.tar ${dir}
		log -t "WLBTD" $(eval echo ${dir}/${tarfile}).tar generated

		# create tar
		tarext="*.tar"
	fi
	sync
fi

# clean-up
rm -rf ${dir}/.tmp-${tarfile} >/dev/null 2>&1
remove_old_tar_and_cmm_files

sync

exit ${script_status}
