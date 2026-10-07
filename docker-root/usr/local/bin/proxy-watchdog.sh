#!/bin/bash
# 代理看门狗：gost（或回退的 danted）长时间运行后可能卡死——TCP 可连但不应答
# SOCKS5 协商（参见 https://github.com/docker-easyconnect/docker-easyconnect/issues/282）。
# 周期性探测 socks5，连续失败则重启代理进程。重启代理不影响 VPN 会话。
interval=${PROXY_WATCHDOG_INTERVAL:-30}
retries=${PROXY_WATCHDOG_RETRIES:-3}
restart_proxy() {
	if [ -x /usr/local/bin/gost ]; then
		killall gost 2> /dev/null
		sleep 1
		gost-proxy.sh &
	else
		killall danted 2> /dev/null
		sleep 1
		/usr/sbin/danted -D -f /run/danted.conf 2> /dev/null &
	fi
}
while sleep "$interval"; do
	fails=0
	until socks5-healthcheck.sh; do
		fails=$((fails + 1))
		[ "$fails" -ge "$retries" ] && break
		sleep 5
	done
	if [ "$fails" -ge "$retries" ]; then
		echo "proxy-watchdog: socks5 探测连续 $retries 次失败，重启代理" >&2
		restart_proxy
	fi
done
