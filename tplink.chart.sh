# shellcheck shell=bash
# no need for shebang - this file is loaded from charts.d.plugin
tplink_passwd=
tplink_stok=
tplink_host="http://tplogin.cn"
tplink_priority=1
tplink_data=

tplink_query() {
    local data path
    data=$1
    path=$(echo $2 | sed -e 's/^\/*/\//')
    if [[ $3 -ne 0 ]];then
        debug="-vvv"
    else
        #debug="--no-progress-meter"
        debug=
    fi
    if [[ "$tplink_stok" != "" ]];then
        url="${tplink_host}/stok=${tplink_stok}${path}"
    else
        url="${tplink_host}${path}"
    fi
    curl -d "${data}" -H "Content-Type: application/json" -H "Origin: http://tplogin.cn" -H "Referer: http://tplogin.cn/" ${debug} "${url}"
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
    local ip=$(drill "${tplink_domain}" | grep "${tplink_domain}" | grep -oP '192.168.*')
    #if [[ "$ip" == "" ]];then
    #    [[ `require_cmd curl` && `require_cmd grep` && `require_cmd sed` ]] || return 1;
    #fi
    return 0;
}

tplink_create() {
    tplink_login || return 1;
    tplink_get
    lan_num=$(echo $tplink_data | jq '.network.lan_status | length')
    cat << EOF
CHART tplink.wan_status 'wan-status' "wan-status" "" wan '' line
DIMENSION phy_status '' absolute 
CHART tplink.wan_speed 'wan-speed' "wan-speed" "bytes" wan '' line
DIMENSION up_speed '' absolute 
DIMENSION down_speed '' absolute
CHART tplink.lan_status 'lan-status' "lan-status" "" lan '' line
DIMENSION 
EOF
}

tplink_update() {
    tplink_get
    cat << VALUESEOF
BEGIN tplink.wan_speed $1
SET up_speed = $(echo $tplink_data | jq '.network.wan_status.up_speed')
SET down_speed = $(echo $tplink_data | jq '.network.wan_status.down_speed')
END
BEGIN tplink.wan_status $1
SET phy_status = $(echo $tplink_data | jq '.network.wan_status.phy_status')
END
VALUESEOF
}

