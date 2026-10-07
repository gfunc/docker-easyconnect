#!/bin/bash
# 代理看门狗，两级保护：
# 1. 代理进程卡死（TCP 可连但不应答 SOCKS5 协商，参见
#    https://github.com/docker-easyconnect/docker-easyconnect/issues/282）→ 重启代理
# 2. VPN 隧道不可达（未登录/会话掉线）→ 摘除代理：端口秒级拒绝，避免上游（如透明代理
#    网关）为每个请求付出整段超时、叠加客户端无退避重试形成连接风暴；VPN 恢复后自动拉起。
# 重启/摘除均不影响 VPN 会话本身。
interval=${PROXY_WATCHDOG_INTERVAL:-30}
retries=${PROXY_WATCHDOG_RETRIES:-3}
tun=${VPN_TUN:-$( [ ATRUST = "$(cat /etc/vpn-type 2>/dev/null)" ] && echo utun7 || echo tun0 )}
suspended=0
vpn_fails=0

start_proxy() {
	if [ -x /usr/local/bin/gost ]; then
		gost-proxy.sh &
	else
		/usr/sbin/danted -D -f /run/danted.conf 2> /dev/null &
	fi
}

vpn_alive() {
	# 层 0：tun 接口存在且其上有路由（未登录时 aTrust/EasyConnect 不推送路由）
	ip link show dev "$tun" &> /dev/null || return 1
	[ -n "$(ip route show dev "$tun" 2>/dev/null)" ] || return 1
	# 层 1：VPN_PROBE_ADDR 显式探测（逗号分隔多个 host:port，任一通即算活）
	[ -z "$VPN_PROBE_ADDR" ] && return 0
	local addr a ok=1
	local IFS=','
	for addr in $VPN_PROBE_ADDR; do
		[ -n "$addr" ] || continue
		if timeout 5 bash -c "exec 3<>/dev/tcp/${addr%:*}/${addr#*:}" 2> /dev/null; then
			ok=0
			break
		fi
	done
	return $ok
}

while sleep "$interval"; do
	# VPN 门控（DISABLE_VPN_GATE 置非空时关闭）
	if [ -z "$DISABLE_VPN_GATE" ]; then
		if vpn_alive; then
			vpn_fails=0
			if [ 1 = "$suspended" ]; then
				echo "proxy-watchdog: vpn 恢复，重新拉起代理" >&2
				start_proxy
				suspended=0
			fi
		else
			vpn_fails=$((vpn_fails + 1))
			if [ 0 = "$suspended" ] && [ "$vpn_fails" -ge "$retries" ]; then
				echo "proxy-watchdog: vpn 不可达（连续 $vpn_fails 次探测失败），摘除代理以避免上游超时堆积" >&2
				killall gost danted 2> /dev/null
				suspended=1
			fi
		fi
		[ 1 = "$suspended" ] && continue
	fi

	# 代理协议健康
	fails=0
	until socks5-healthcheck.sh; do
		fails=$((fails + 1))
		[ "$fails" -ge "$retries" ] && break
		sleep 5
	done
	if [ "$fails" -ge "$retries" ]; then
		echo "proxy-watchdog: socks5 探测连续 $retries 次失败，重启代理" >&2
		killall gost danted 2> /dev/null
		sleep 1
		start_proxy
	fi
done
