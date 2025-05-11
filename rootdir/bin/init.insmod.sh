#!/vendor/bin/sh

####################################################################
### init.insmod.cfg format:                                      ###
### -----------------------------------------------------------  ###
### [insmod|setprop|enable/modprobe|insmod_16k] [path|prop name] ###
### ...                                                          ###
####################################################################

function print_msg()
{
  echo $1 > /dev/kmsg
}

function get_module_dir()
{
  local type=$1
  modules_dir=
  for f in /${type}/lib/modules/*/modules.dep /${type}/lib/modules/modules.dep /${type}_dlkm/lib/modules/*/modules.dep; do
    if [[ -f "$f" ]]; then
      modules_dir="$(dirname "$f")"
      break
    fi
  done
  echo "${modules_dir}"
}

if [ $# -eq 1 ]; then
  cfg_file=$1
else
  # Set property even if there is no insmod config
  # to unblock early-boot trigger
  setprop vendor.common.modules.ready
  setprop vendor.device.modules.ready
  exit 1
fi

if [ "$cfg_file" == "system_dlkm" ]; then
  gc_pgsize=$(getconf PAGE_SIZE)
  if [ "${gc_pgsize}" -eq 16384 ]; then
    print_msg "16K pagesize cannot load system_dlkm module, exiting..."
    exit 0
  fi

  modules_dir=$(get_module_dir system)
  if [[ -z "${modules_dir}" ]]; then
    print_msg "Unable to locate kernel modules directory"
    exit 1
  fi
  print_msg "modules_dir is ${modules_dir}"
  modprobe -s -b -d "${modules_dir}" --all=${modules_dir}/modules.load
#  if [ $? -eq 0 ]; then
    setprop vendor.system_dlkm.modules.ready true
#  fi
elif [ "$cfg_file" == "vendor_dlkm" ]; then
  gc_pgsize=$(getconf PAGE_SIZE)
  if [ "${gc_pgsize}" -eq 16384 ]; then
    print_msg "16K pagesize cannot load vendor_dlkm module, exiting..."
    setprop vendor.vendor_dlkm.modules.ready true
    exit 0
  fi

  modules_dir=$(get_module_dir vendor)
  if [[ -z "${modules_dir}" ]]; then
    print_msg "Unable to locate kernel modules directory"
    exit 1
  fi
  print_msg "modules_dir is ${modules_dir}"

  modprobe -s -b -d "${modules_dir}" --all=${modules_dir}/modules.load
  if [ $? -eq 0 ]; then
    setprop vendor.vendor_dlkm.modules.ready true
  else
    print_msg "modprobe failed! Loading modules using insmod"
    modules_load="${modules_dir}/modules.load"
    print_msg "Modules load = $modules_load"
    if [ ! -f $modules_load ]; then
      print_msg "$modules_load not found!"
      exit 1
    fi
    for m in $(cat ${modules_load}); do
      print_msg "insmod ${modules_dir}/${m}"
      insmod ${modules_dir}/${m}
    done
    setprop vendor.vendor_dlkm.modules.ready true
  fi

elif [ -f $cfg_file ]; then
  modules_dir=$(get_module_dir vendor)
  while IFS="|" read -r action arg
  do
    case $action in
      "insmod") insmod $arg ;;
      "setprop") setprop $arg 1 ;;
      "enable") echo 1 > $arg ;;
      "modprobe") modprobe -s -a -d "${modules_dir}" $arg ;;
      "insmod_16k")
        gc_pgsize=$(getconf PAGE_SIZE)
        if [ "${gc_pgsize}" -eq 16384 ]; then
          insmod $arg
        fi
        ;;
    esac
  done < $cfg_file
fi
