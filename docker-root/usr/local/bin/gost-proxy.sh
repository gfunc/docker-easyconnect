#!/bin/bash
# gost 单进程同时提供 socks5（1080，含 UDP 转发）与 http（8888）代理。
# SOCKS_USER 与 SOCKS_PASSWD 同时设置时启用认证（同时作用于两种代理），
# 密码中不能包含 URL 特殊字符（@ : / 等）。
auth=
if [ -n "$SOCKS_USER" ] && [ -n "$SOCKS_PASSWD" ]; then
	auth="${SOCKS_USER}:${SOCKS_PASSWD}@"
	echo "use proxy auth: $SOCKS_USER:$SOCKS_PASSWD"
fi
# 后台启动并退出（与 danted 的 daemonize 行为一致），否则 start.sh 的 wait 会被阻塞，
# 导致其后的 start-sangfor.sh（VPN 启动）永远不会执行
/usr/local/bin/gost -L "socks5://${auth}:1080?udp=true" -L "http://${auth}:8888" &
