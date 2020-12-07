# shellcheck shell=bash
# no need for shebang - this file is loaded from charts.d.plugin
tplink_passwd=
tplink_stok=
tplink_domain="tplogin.cn"
tplink_host="http://${tplink_domain}"
tplink_data=
tplink_total_upload=0
tplink_total_download=0
tplink_total_data_path=/tmp/tplink.netdata.data
tplink_total_data_write_freq=300
tplink_total_data_retention=604800
tplink_total_data_start=0
tplink_first_load=true
declare -A tplink_host_total


tplink_query() {
    local data path
    data=$1
    path=$(echo "$2" | sed -e 's/^\/*/\//')
    if [[ "$tplink_stok" != "" ]];then
        url="${tplink_host}/stok=${tplink_stok}${path}"
    else
        url="${tplink_host}${path}"
    fi
    curl -s -d "${data}" -H "Content-Type: application/json" -H "Origin: ${tplink_host}" -H "Referer: {$tplink_host}" "${url}"
}

tplink_login() {
    if [[ "$tplink_stok" == "" ]];then
        tplink_stok=$(tplink_query "{\"method\":\"do\",\"login\":{\"password\":\"${tplink_passwd}\"}}" '/' | jq -r ".stok")
    fi
    [[ "$tplink_stok" != "" ]] || return 1;
}

tplink_get() {
    tplink_data=$(tplink_query '{"hosts_info":{"table":"online_host"},"network":{"name":["wan_status","lan_status"]},"method":"get"}' '/ds')
}

tplink_check() {
    local ip
    ip=$(drill "${tplink_domain}" | grep "${tplink_domain}" | grep -oP '192.168.*')
    if [[ "$ip" == "" ]];then
        return 1;
    fi
    return 0;
}

tplink_host_info() {
    local host_macs total_host_macs new_host_macs hostname speed speed_dimensions total_dimensions tmp key_prefix key
    mapfile -t host_macs < <(echo "$tplink_data" | jq -r '.hosts_info.online_host[][].mac')
    speed_dimensions=""
    total_dimensions=""
    declare -A total_host_macs
    for key in "${!tplink_host_total[@]}"; do
        key="${key%_up}"
        key="${key%_down}"
        key="${key//*(*_)/}"
        total_host_macs["$key"]=1
    done
    if $tplink_first_load ;then
        for key in "${!tplink_host_total[@]}"; do
            speed_dimensions="${speed_dimensions}\nDIMENSION '${key}' '' absolute"
            total_dimensions="${total_dimensions}\nDIMENSION '${key}' '' absolute"
        done
    fi
    mapfile -t new_host_macs < <(echo "${host_macs[@]}" "${total_host_macs[@]}" "${total_host_macs[@]}" | tr ' ' '\n' | sort | uniq -u)
    if [[ "${new_host_macs[*]}" != "" ]];then
        for host_mac in "${new_host_macs[@]}";do
            hostname=$(echo "$tplink_data" | jq -r ".hosts_info.online_host[][] | select(.mac == \"${host_mac}\") | .hostname")
            key_prefix=${hostname}_${host_mac}
            speed_dimensions="${speed_dimensions}\nDIMENSION '${key_prefix}_up' '' absolute"
            speed_dimensions="${speed_dimensions}\nDIMENSION '${key_prefix}_down' '' absolute"
            total_dimensions="${total_dimensions}\nDIMENSION '${key_prefix}_up' '' absolute"
            total_dimensions="${total_dimensions}\nDIMENSION '${key_prefix}_down' '' absolute"
            [ ${tplink_host_total[${key_prefix}_up]+exist} ] || tplink_host_total[${key_prefix}_up]=0
            [ ${tplink_host_total[${key_prefix}_up]+exist} ] || tplink_host_total[${key_prefix}_down]=0
        done
    fi
    if [[ "${speed_dimensions}" != "" ]]; then
        echo "CHART tplink.host_speed 'host-speed' 'host-speed' 'KiB/s' 'online-host' '' stacked"
        echo -e "$speed_dimensions"
        echo "CHART tplink.host_total 'host-total' 'host-total' 'KiB' 'online-host' '' area"
        echo -e "$total_dimensions"
    fi
    echo "BEGIN tplink.host_speed"
    for host_mac in "${host_macs[@]}";do
        hostname=$(echo "$tplink_data" | jq -r ".hosts_info.online_host[][] | select(.mac == \"${host_mac}\") | .hostname")
        key_prefix=${hostname}_${host_mac}
        speed=$(echo "$tplink_data" | jq -r ".hosts_info.online_host[][] | select(.mac == \"${host_mac}\") | .down_speed")
        speed=$((speed/1024))
        tmp=${tplink_host_total["${key_prefix}_down"]}
        tplink_host_total["${key_prefix}_down"]=$((tmp+speed))
        echo "SET ${key_prefix}_down=${speed}"
        speed=$(echo "$tplink_data" | jq -r ".hosts_info.online_host[][] | select(.mac == \"${host_mac}\") | .up_speed")
        speed=$((speed/1024))
        tmp=${tplink_host_total["${key_prefix}_up"]}
        tplink_host_total["${key_prefix}_up"]=$((tmp+speed))
        echo "SET ${key_prefix}_up=-${speed}"
    done
    echo "END"
    echo "BEGIN tplink.host_total"
    for key in "${!tplink_host_total[@]}";do
        echo "SET $key = ${tplink_host_total[$key]}"
    done
    echo "END"
}

tplink_dump_total_info() {
    local last_write
    last_write=$(stat --print %Y ${tplink_total_data_path})
    if [[ -e ${tplink_total_data_path} && $(date +%s) -lt $((tplink_total_data_write_freq+last_write)) ]];then
        return
    fi
    truncate --size=0 ${tplink_total_data_path}
    #echo "${tplink_total_data_start}\n${tplink_total_upload}\n${tplink_total_download}" >> ${tplink_total_data_path}
    printf "%b\n%b\n%b\n" "${tplink_total_data_start}" "${tplink_total_upload}" "${tplink_total_download}" >> ${tplink_total_data_path}
    for key in "${!tplink_host_total[@]}";do
        echo "$key=${tplink_host_total[$key]}" >> ${tplink_total_data_path}
    done
}

tplink_init_total_info() {
    local total_data tmp line host_start_idx
    if [[ ! -e ${tplink_total_data_path} ]];then
        tplink_total_data_start=$(date +%s)
        return 0
    fi
    mapfile -t total_data < ${tplink_total_data_path}
    tplink_total_data_start=${total_data[0]}
    tmp=$(date +%s)
    if [[ $tmp -gt $((tplink_total_data_start+tplink_total_data_retention)) ]];then
        tplink_total_data_start=$tmp
        return 0
    fi
    if [[ "${total_data[1]}" =~ "=" ]];then
        # old data version, without total up&down
        host_start_idx=1
    else # new version, with total up&down
        tplink_total_upload=${total_data[1]}
        tplink_total_download=${total_data[2]}
        host_start_idx=3
    fi
    for line in "${total_data[@]:${host_start_idx}}";do
        IFS='=' read -r -a tmp <<< "$line"
        tplink_host_total[${tmp[0]}]=${tmp[1]}
    done
}

tplink_create() {
    tplink_login || return 1;
    tplink_get
    local lan_dimensions
    tplink_lan_num=$(echo "$tplink_data" | jq '.network.lan_status | length')
    for ((i=1;i<=tplink_lan_num;i++));do
        lan_dimensions="${lan_dimensions}
DIMENSION phy_status_${i} '' absolute"
    done
    tplink_init_total_info
    cat << EOF
CHART tplink.wan_status 'wan-status' 'wan-status' '' 'wan' '' line
DIMENSION phy_status '' absolute
CHART tplink.wan_speed 'wan-speed' 'wan-speed' 'KiB/s' 'wan' '' area
DIMENSION up_speed '' absolute
DIMENSION down_speed '' absolute
CHART tplink.wan_total 'wan-total' 'wan-total' 'KiB' 'wan' '' area
DIMENSION upload '' absolute
DIMENSION download '' absolute
CHART tplink.lan_status 'lan-status' 'lan-status' '' 'lan' '' line
${lan_dimensions}
CHART tplink.online_host 'online-host' 'online-host' 'p' 'online-host' '' stacked
DIMENSION wifi '' absolute
DIMENSION lan '' absolute
EOF
}

tplink_update() {
    tplink_get
    local lan_status_sets wan_down_speed wan_up_speed
    for ((i=1;i<=tplink_lan_num;i++));do
        lan_status_sets="${lan_status_sets}
SET phy_status_${i} = $(echo "$tplink_data" | jq -r ".network.lan_status.lan_${i}.phy_status")"
    done
    wan_up_speed=$(echo "$tplink_data" | jq '.network.wan_status.up_speed')
    wan_down_speed=$(echo "$tplink_data" | jq '.network.wan_status.down_speed')
    tplink_total_upload=$((tplink_total_upload+wan_up_speed))
    tplink_total_download=$((tplink_total_download+wan_down_speed))
    cat << VALUESEOF
BEGIN tplink.wan_speed $1
SET up_speed = -$wan_up_speed
SET down_speed = $wan_down_speed
END
BEGIN tplink.wan_total $1
SET upload = -$tplink_total_upload
SET download = $tplink_total_download
END
BEGIN tplink.wan_status $1
SET phy_status = $(echo "$tplink_data" | jq '.network.wan_status.phy_status')
END
BEGIN tplink.lan_status $1
${lan_status_sets}
END
BEGIN tplink.online_host $1
SET wifi = $(echo "$tplink_data" | jq '.hosts_info.online_host[][] | select(.wifi_mode=="1") | .host_name' | wc -l)
SET lan = $(echo "$tplink_data" | jq '.hosts_info.online_host[][] | select(.wifi_mode=="0") | .host_name' | wc -l)
END
VALUESEOF
tplink_host_info "$1"
tplink_dump_total_info
}

