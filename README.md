# tplink.netdata
tplink plugin of netdata.
Only test with WDR7660

## notices
### passwd
The `tplink_passwd` is not your real passwd, It's just a value
with encoded by tplink.

You can found it when you login the tplink web page.

### Total data
total data  is not correct value,

I have not found the api to get the value,

just accumulate the `speed` value.

## install
```bash
make install tplink_passwd=<the passwd>
# install with sudo
make install use_sudo=1 ...
# install to remote
make install host=<your host> ...
```
