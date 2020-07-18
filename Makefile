use_sudo=
host=
upload_conf=
netdata_dir=/usr/lib/netdata
netdata_web_dir=/usr/share/netdata/web
netdata_conf_dir=/etc/netdata
chart_path=$(netdata_dir)/charts.d/tplink.chart.sh
plugin_bin=$(netdata_dir)/plugins.d/charts.d.plugin
dashboard_path=$(netdata_web_dir)/tplink.html
conf_path=$(netdata_conf_dir)/charts.d/tplink.conf
user=netdata
group=netdata

ifneq ($(use_sudo),)
sudo=sudo
endif
ifeq ($(host),)
run_cmd=$(sudo)
else
run_cmd=ssh $(host) $(sudo)
endif

tplink_passwd=

check_passwd:
ifneq ($(upload_conf),)
ifeq ($(tplink_passwd),)
		$(error "tplink_passwd is required")
else
		mkdir -p build
		sed 's/tplink_passwd=/tplink_passwd="$(tplink_passwd)"/' tplink.conf > build/tplink.conf
endif
endif


upload: shellcheck check_passwd
ifeq ($(host),)
		$(run_cmd) cp tplink.chart.sh $(chart_path)
		$(run_cmd) cp tplink.html $(dashboard_path)
		$(run_cmd) cp build/tplink.conf $(conf_path)
else
		rsync --rsync-path='$(sudo) rsync' tplink.chart.sh $(host):$(chart_path)
		rsync --rsync-path='$(sudo) rsync' tplink.html $(host):$(dashboard_path)
		rsync --rsync-path='$(sudo) rsync' build/tplink.conf $(host):$(conf_path)
endif
		$(run_cmd) chown $(user):$(group) $(chart_path) $(dashboard_path)

debug: upload
		$(run_cmd) $(plugin_bin) debug 1 tplink

install: upload
		$(run_cmd) systemctl restart netdata

clean:
		rm -r build

shellcheck:
		shellcheck tplink.chart.sh

