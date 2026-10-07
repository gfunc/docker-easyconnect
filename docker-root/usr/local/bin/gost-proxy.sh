#!/bin/bash
# gost 单进程同时提供 socks5（1080）与 http（8888）代理。
# 认证：SOCKS_USER 与 SOCKS_PASSWD 同时设置时启用（同时作用于两种代理），
# 密码中不能包含双引号和反斜杠。
# split-DNS：VPN_DNS 设置时，VPN_DNS_DOMAINS（逗号分隔域名后缀，如 .uco.com）
# 命中的域名经 VPN 指定的 DNS（如内网 DNS，需隧道可达）解析，其余走系统默认。
conf=/run/gost.yaml

esc() { local s=${1//\\/\\\\}; s=${s//\"/\\\"}; printf '"%s"' "$s"; }

auth_block() {
	if [ -n "$SOCKS_USER" ] && [ -n "$SOCKS_PASSWD" ]; then
		echo "    auth:"
		echo "      username: $(esc "$SOCKS_USER")"
		echo "      password: $(esc "$SOCKS_PASSWD")"
	fi
}

{
	echo "log:"
	echo "  level: info"
	echo "services:"
	for svc in "socks5 1080" "http 8888"; do
		set -- $svc
		echo "- name: $1"
		echo "  addr: :$2"
		echo "  handler:"
		echo "    type: $1"
		# resolver 必须挂 handler 级：挂 service 级时 gost 不会按 matcher 回落到后续 resolver
		[ -n "$VPN_DNS" ] && echo "    resolver: vpn-dns"
		auth_block
		echo "  listener:"
		echo "    type: tcp"
	done
	if [ -n "$VPN_DNS" ]; then
		echo "resolvers:"
		echo "- name: vpn-dns"
		echo "  matcher:"
		echo "    domain:"
		IFS=','
		for d in $VPN_DNS_DOMAINS; do
			[ -n "$d" ] || continue
			echo "    - $(esc "$d")"
			# 前缀带点时同时匹配裸域（.uco.com 同时命中 uco.com）
			case "$d" in .*) echo "    - $(esc "${d#.}")" ;; esac
		done
		unset IFS
		echo "  nameservers:"
		echo "  - addr: udp://$VPN_DNS"
		echo "    prefer: ipv4"
		echo "    timeout: 3s"
		# 兜底 resolver：未命中 VPN 域名的走容器系统 DNS（docker/podman 均取自 resolv.conf）
		defdns=$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf 2>/dev/null)
		if [ -n "$defdns" ]; then
			echo "- name: default"
			echo "  nameservers:"
			echo "  - addr: udp://$defdns"
		fi
	fi
} > "$conf"

[ -n "$SOCKS_USER" ] && [ -n "$SOCKS_PASSWD" ] && echo "use proxy auth: $SOCKS_USER:$SOCKS_PASSWD"

# 后台启动并退出（与 danted 的 daemonize 行为一致），否则 start.sh 的 wait 会被阻塞，
# 导致其后的 start-sangfor.sh（VPN 启动）永远不会执行
/usr/local/bin/gost -C "$conf" &
