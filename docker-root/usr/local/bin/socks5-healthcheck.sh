#!/bin/bash
# SOCKS5 探测：发送无认证 greeting（05 01 00），代理正常时应立刻收到以 05 开头的应答
# （00 无需认证，02 需要用户名密码）。gost/danted 卡死时 TCP 握手仍可完成但不再应答
# 协议，且可能没有日志可查，故以协议探测代替进程存活检查。
# 注意不能用 busybox nc：它在 stdin EOF 后立即退出，等不到回应。
[ -n "$NODANTED" ] && exit 0
reply="$(timeout 10 bash -c 'exec 3<>/dev/tcp/127.0.0.1/1080; printf "\005\001\000" >&3; head -c 2 <&3' 2>/dev/null | od -An -tx1)"
case "${reply// /}" in
	05*) exit 0 ;;
	*)
		echo "socks5 greeting got no valid reply: ${reply:-<empty>}" >&2
		echo "hint: 若日志中有 '摘除代理' 字样，属于 VPN 不可达时看门狗的预期行为（docker logs 可见）" >&2
		exit 1
		;;
esac
