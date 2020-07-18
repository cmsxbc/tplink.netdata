# shellcheck shell=bash
# no need for shebang - this file is loaded from charts.d.plugin
tplink_passwd=
tplink_stok=
tplink_domain="tplogin.cn"
tplink_host="http://${tplink_domain}"
tplink_data=
tplink_online_host_macs=
tplink_total_upload=0
tplink_total_download=0
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
    local host_macs new_host_macs hostname speed speed_dimensions total_dimensions tmp key_prefix
    mapfile -t host_macs < <(echo "$tplink_data" | jq -r '.hosts_info.online_host[][].mac')
    mapfile -t new_host_macs < <(echo "${host_macs[@]}" "${tplink_online_host_macs[@]}" "${tplink_online_host_macs[@]}" | tr ' ' '\n' | sort | uniq -u)
    tplink_online_host_macs=("${host_macs[@]}")
    if [[ "${new_host_macs[*]}" != "" ]];then
        speed_dimensions=""
        total_dimensions=""
        for host_mac in "${new_host_macs[@]}";do
            hostname=$(echo "$tplink_data" | jq -r ".hosts_info.online_host[][] | select(.mac == \"${host_mac}\") | .hostname")
            key_prefix=${hostname}_${host_mac}
            speed_dimensions="${speed_dimensions}\nDIMENSION '${key_prefix}_up' '' absolute"
            speed_dimensions="${speed_dimensions}\nDIMENSION '${key_prefix}_down' '' absolute"
            total_dimensions="${total_dimensions}\nDIMENSION '${key_prefix}_up' '' absolute"
            total_dimensions="${total_dimensions}\nDIMENSION '${key_prefix}_down' '' absolute"
            tplink_host_total[${key_prefix}_up]=0
            tplink_host_total[${key_prefix}_down]=0
        done
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

tplink_create() {
    tplink_login || return 1;
    tplink_get
    local lan_dimensions
    tplink_lan_num=$(echo "$tplink_data" | jq '.network.lan_status | length')
    lan_dimensions=
    for ((i=1;i<=tplink_lan_num;i++));do
        lan_dimensions="${lan_dimensions}
DIMENSION phy_status_${i} '' absolute"
    done
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
}

