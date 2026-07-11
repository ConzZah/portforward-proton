#!/usr/bin/env sh

### /// portforward-proton.sh // ConzZah // 2026-07-11 01:54 ///


## NOTE: THIS PROJECT AUTOMATES ALL OF THE STEPS DESCRIBED HERE, 
## PLUS ERROR CHECKING AND UFW SETUP:
## https://protonvpn.com/support/port-forwarding-manual-setup#linux 


# shellcheck disable=SC2009
# REASON: pgrep is not POSIX.


init () {
## check if we're 1000 or 0 (normal user or root)
doso=""
[ "$(id -u)" = "1000" ] && {
command -v doas >/dev/null && doso="doas"
command -v sudo >/dev/null && doso="sudo"
}

## depcheck
missing_deps=""
deps="sha1sum expect uname curl grep sort uniq sed cut tr ip"

for dep in $deps; do
! command -v "$dep" >/dev/null && missing_deps="${dep} ${missing_deps}"
done

## if $missing_deps is nonzero, show the user what's missing, and exit.
[ -n "$missing_deps" ] && \
printf '\n%s\n%s\n\n' "--> ERROR: THE FOLLOWING DEPENDENCIES ARE MISSING:" "$missing_deps" && exit 1

## check if $natpmpc is installed
## if it isn't, download a statically linked executable for the users architecture.
printf '%s\n' "--> checking for natpmpc.."
natpmpc="natpmpc"
command -v natpmpc >/dev/null && \
printf '%s\n' "--> natpmpc found."

! command -v natpmpc >/dev/null && {
printf '%s\n' "--> natpmpc not found, checking for natpmpc-static.."
arch="$(uname -m)"
case "$arch" in
aarch64) ;;
armv7l) ;;
x86_64) ;;
i686) ;;
*) printf '%s\n' "--> ERROR: natpmpc-static isn't available for your architecture. pls install it from your package manager instead." && exit 1 ;;
esac

## sha1s of natpmpc-static for all of the above architectures
natpmpc_sha1="2aa138098167c1eaa895ef91a73c45d66db32e07 cc6fcced4e684a2ca83dfa6702180b8423b76da6 dd160d7820fa52180ebff1a3c96442f39d08d257 8599f5021b61e33edec6cba3124c386d988d707d"
natpmpc_dir="${HOME}/.natpmpc-static"
mkdir -p "${natpmpc_dir}"
natpmpc="${natpmpc_dir}/natpmpc-static-${arch}"

## if $natpmpc ^^^ doesn't exist, download it.
[ ! -f "${natpmpc}" ] && printf '%s\n' "--> downloading: natpmpc-static-${arch}" && \
curl -Lo "${natpmpc}" "https://github.com/ConzZah/libnatpmp/releases/download/natpmpc-static/natpmpc-static-${arch}"

## get sha1 of the local file
local_sha1="$(sha1sum "${natpmpc}"| cut -d ' ' -f 1)"

## loop thru $natpmpc_sha1 to find a $matched_sha1
matched_sha1=""
for sha1 in $natpmpc_sha1; do
[ "$sha1" = "$local_sha1" ] && matched_sha1="$sha1" && break
done

## if $matched_sha1 is zero, the download is corrupted.
[ -z "$matched_sha1" ] && printf '%s\n' "--> ERROR: DOWNLOAD CORRUPTED" && {
[ -f "$natpmpc" ] && rm -f "$natpmpc"
exit 1
}

## ensure $natpmpc is executable
[ ! -x "$natpmpc" ] && chmod u+x "$natpmpc"
printf '%s\n' "--> natpmpc-static found."
}


### probe if we are even connected to a protonvpn server that supports p2p
## NOTE: natpmpc's output is BUFFERED, which is why we need to use --> unbuffer. <--
## i did try to use stdbuf for this, but it DOES NOT WORK with statically-linked executables.
## now, if you'd try to redirect natpmpc's output to a file without unbuffer, the file would stay empty.
probe="/tmp/natpmprobe"
echo '' > "${probe}"
printf '%s\n' "--> probing if protonvpn server has port-forwarding enabled.."
eval "unbuffer $natpmpc -g 10.2.0.1 > ${probe} &"
pmpid="$!"
sleep 2
## kill "$pmpid" only if it's still running
ps -aux| grep "$pmpid"| grep -qv 'grep' && \
kill -9 "$pmpid" >/dev/null 2>&1

## if we find any status-code that has '-' (minus) in front of it, then the user should check their configs.
## NOTE: in natpmpc, status-codes that start with a minus are ALWAYS considered errors.
grep -q '\-.*' "${probe}" && \
printf '\n%s\n\n%s\n\n%s\n\n' "--> ERROR: PORT-FORWARDING IMPOSSIBLE. CHECK YOUR VPN CONFIGURATION." "== LOG ==" "$(cat "$probe")" && exit 1

## if we're still here, might aswell tell the user that the probe was successful
printf '%s\n' "--> probe successful, port-forwarding possible."

## find out which $port will be assigned to our machine, so we may add ufw rules.
port=""
port="$($natpmpc -a 1 0 udp 60 -g 10.2.0.1| grep -o 'public port.*protocol'| cut -d ' ' -f 3)"
}


add_ufw_rules () {
## edit $PATH, so ufw can be found
PATH="$PATH:/usr/sbin:/sbin"
ufw_comment="created by: portforward-proton.sh"
found_ufw=""
printf '%s\n' "--> checking for ufw.."

## if ufw can't be found, abort.
! command -v ufw >/dev/null && printf '%s\n' "--> ufw can't be found, skipping." && return 1

## if we're still here, check if ufw is inactive
printf '%s\n' "--> found ufw."
printf '%s\n' "--> checking if ufw is active.."
$doso ufw status| grep -q 'Status: inactive' && \
printf '%s\n' "--> ufw is inactive, won't modify anything." && return
printf '%s\n' "--> ufw is active."

## if ufw is active, check for leftover rules created by portforward-proton.sh
## NOTE: THIS IS ONLY HERE AS A SAFETY MEASURE!!
## NORMALLY THERE WILL BE NO PORTS LEFT OPEN WHEN YOU EXIT (by ctrl+c or when natpmpc fails).
## the only way it will happen, is when cleanup didn't get a chance to run. (which would be the users fault.)
## (for example; when the user just closes the terminal window, despite the clear warning that a process is still running)
## i can only do so much to protect my users from their own actions, but that's why i license everything under the MIT-LICENSE.
leftover_rules=""
leftover_rules="$($doso ufw status| tr -s ' '| grep -o ".*${ufw_comment}"| cut -d ' ' -f 1| sort| uniq)"

## if we have $leftover_rules, deal with them
[ -n "$leftover_rules" ] && {
for leftover in $leftover_rules; do 
$doso ufw delete allow "$leftover" >/dev/null
done
}

## allow our $port
printf '%s\n' "--> creating ufw rule for port: $port"
[ -n "$port" ] && $doso ufw allow "$port" comment "$ufw_comment"
found_ufw="1"
}


change_qbittorrent_settings () {
## NOTE: we only attempt to change settings when qBittorrent is found AND NOT currently running
## qBittorrent is also not a strict requirement to run this script, 
## since port-forwarding can also be used for p2p online games or other torrent clients.
## NOTE: speaking of other torrent clients: i MIGHT look into transmission and deluge, but no promises.
printf '%s\n' "--> checking for qBittorrent.."
! command -v qbittorrent >/dev/null && printf '%s\n' "--> NOTE: qBittorrent was not found!" && return 1
printf '%s\n' "--> qBittorrent found."
## check if qbittorrent is running
qbittorrent_pid=""
qbittorrent_pid="$(ps aux| grep qbittorrent| grep -v grep| tr -s ' '| cut -d ' ' -f 2)"

## if $qbittorrent_pid is nonzero, then qbittorrent is running, (we can't change anything while it is)
## should that be the case, we need to exit here.
[ -n "$qbittorrent_pid" ] && \
printf '\n%s\n\n%s\n\n' \
"--> ERROR: qBittorrent is running, won't change any settings." \
"--> PLEASE SHUT DOWN QBITTORRENT AND RUN THIS SCRIPT AGAIN." && return 1

## change Session\Port in qBittorrent.conf to $port
printf '%s\n' "--> looking for: qBittorrent.conf.."
qbittorrent_conf="$HOME/.config/qBittorrent/qBittorrent.conf"
[ ! -f "$qbittorrent_conf" ] && printf '%s\n' "--> ERROR: COULDN'T FIND: $qbittorrent_conf" && exit 1

[ -f "$qbittorrent_conf" ] && {
printf '%s\n' "--> qBittorrent.conf found."
## find the $old_session_port,
## and change it to the new $port, if they don't match.
old_session_port="$(grep -i 'port' "$qbittorrent_conf"| grep 'Session\\Port'| cut -d '=' -f 2)"

## only make the change, if $old_session_port is nonzero
[ -n "$old_session_port" ] && [ "$old_session_port" != "$port" ] && \
printf '%s\n' "--> changing qBittorrent port from: $old_session_port to: $port" && \
sed -i "s/${old_session_port}/${port}/g" "$qbittorrent_conf"

## change session\interface to tun0, if tun0 is active, and was something else than tun0 before.
ip a| grep -q 'tun0' && {
current_session_interface=""
current_session_interface="$(grep -i -m1 'interface' "$qbittorrent_conf"| cut -d '=' -f 2)"
[ -n "$current_session_interface" ] && [ "$current_session_interface" != "tun0" ] && \
sed -i "s#$current_session_interface#tun0#g" "$qbittorrent_conf"
}

## disable the option: 'Use UPnP / NAT-PMP port forwarding from my router'
grep -q 'PortForwardingEnabled=true' "$qbittorrent_conf" && \
sed -i "s#PortForwardingEnabled=true#PortForwardingEnabled=false#g" "$qbittorrent_conf"
}
}


main () {
## run the loop to refresh our lease
printf '%s\n%s\n%s\n' "=======================" "--> STARTING MAIN LOOP" "======================="
while true
do date
if
$natpmpc -a 1 0 udp 60 -g 10.2.0.1
then
$natpmpc -a 1 0 tcp 60 -g 10.2.0.1
sleep 45
else
{ printf '%s\n' "--> NATPMPC ERROR"; cleanup ;}
fi
done
}


cleanup () {
## if we exit the script, delete the ufw rules we set & exit, 
## delete the added ufw rules (on natpmpc failure or INT, TERM.)
## so we don't have useless open ports, which would be very dangerous.
[ -n "$found_ufw" ] && {
$doso ufw status| tr -s ' '| grep -q "$port ALLOW.*" && \
printf '%s\n' "--> deleting ufw rule for port: $port" && \
$doso ufw delete allow "$port" && \
printf '%s\n' "--> deleted ufw rule for port: $port"
}
printf '%s\n' "--> SEE YA :D" && exit
}


## it's a trap!!
## https://www.youtube.com/watch?v=piVnArp9ZE0
trap cleanup INT TERM


init
change_qbittorrent_settings
add_ufw_rules 
main
