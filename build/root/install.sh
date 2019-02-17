#!/bin/bash

# exit script if return code != 0
set -e

# build scripts
####

# download build scripts from github
curl --connect-timeout 5 --max-time 600 --retry 5 --retry-delay 0 --retry-max-time 60 -o /tmp/scripts-master.zip -L https://github.com/binhex/scripts/archive/master.zip

# unzip build scripts
unzip /tmp/scripts-master.zip -d /tmp

# move shell scripts to /root
mv /tmp/scripts-master/shell/arch/docker/*.sh /root/

# pacman packages
####

# call pacman db and package updater script
source /root/upd.sh

# flood currently requires nodejs v10 (package name nodejs-lts-dubnium), not v11 (package name nodejs) thus we force install of v10 before we proceed to install npm (dependency nodejs)
pacman -S nodejs-lts-dubnium --needed --noconfirm

# define pacman packages
pacman_packages="git nginx php-fpm rsync openssl tmux mediainfo npm php-geoip unrar zip unzip libx264 libvpx libtorrent rtorrent"

# install compiled packages using pacman
if [[ ! -z "${pacman_packages}" ]]; then
	pacman -S --needed $pacman_packages --noconfirm
fi

# aur packages
####

# define aur packages
aur_packages="rutorrent autodl-irssi-community"

# call aur install script (arch user repo) - note true required due to autodl-irssi error during install
source /root/aur.sh

# github releases
####

# download flood ui for rtorrent
/root/github.sh -df "github-download.zip" -dp "/tmp" -ep "/tmp/extracted" -ip "/etc/webapps/flood" -go "jfurrow" -gr "flood" -rt "source" -db "master"

# flood requires make for npm packages
pacman -S base-devel --needed --noconfirm

# install npm package 'forever' - this is used to restart flood on crash
npm install -g forever

# run npm install -  note do not attempt to run 'npm run build' at this point as we need config.js
cd "/etc/webapps/flood" && npm install

# after flood install remove base devel excluding useful core packages
pacman -Ru $(pacman -Qgq base-devel | grep -v awk | grep -v pacman | grep -v sed | grep -v grep | grep -v gzip | grep -v which) --noconfirm

# download autodl-irssi community plugin
/root/github.sh -df "github-download.zip" -dp "/tmp" -ep "/tmp/extracted" -ip "/usr/share/webapps/rutorrent/plugins/autodl-irssi" -go "autodl-community" -gr "autodl-rutorrent" -rt "source"

# download htpasswd (problems with apache-tools and openssl 1.1.x)
/root/curly.sh -rc 6 -rw 10 -of /tmp/htpasswd.tar.gz -url "https://github.com/binhex/arch-packages/raw/master/compiled/htpasswd.tar.gz"

# extract compiled version of htpasswd
tar -xvf /tmp/htpasswd.tar.gz -C /

# config - php
####

php_ini="/etc/php/php.ini"

# configure php memory limit to improve performance
sed -i -e "s~.*memory_limit\s\=\s.*~memory_limit = 512M~g" "${php_ini}"

# configure php max execution time to try and prevent timeout issues
sed -i -e "s~.*max_execution_time\s\=\s.*~max_execution_time = 300~g" "${php_ini}"

# configure php max file uploads to prevent issues with reaching limit of upload count
sed -i -e "s~.*max_file_uploads\s\=\s.*~max_file_uploads = 200~g" "${php_ini}"

# configure php max input variables (get/post/cookies) to prevent warnings issued
sed -i -e "s~.*max_input_vars\s\=\s.*~max_input_vars = 10000~g" "${php_ini}"

# configure php upload max filesize to prevent large torrent files failing to upload
sed -i -e "s~.*upload_max_filesize\s\=\s.*~upload_max_filesize = 20M~g" "${php_ini}"

# configure php post max size (linked to upload max filesize)
sed -i -e "s~.*post_max_size\s\=\s.*~post_max_size = 25M~g" "${php_ini}"

# configure php with additional php-geoip module
sed -i -e "/.*extension=gd/a extension=geoip" "${php_ini}"

# configure php to enable sockets module (used for autodl-irssi plugin)
sed -i -e "s~.*extension=sockets~extension=sockets~g" "${php_ini}"

# configure php-fpm to use tcp/ip connection for listener
php_fpm_ini="/etc/php/php-fpm.conf"

echo "" >> "${php_fpm_ini}"
echo "; Set php-fpm to use tcp/ip connection" >> "${php_fpm_ini}"
echo "listen = 127.0.0.1:7777" >> "${php_fpm_ini}"

# configure php-fpm listener for user nobody, group users
echo "" >> "${php_fpm_ini}"
echo "; Specify user listener owner" >> "${php_fpm_ini}"
echo "listen.owner = nobody" >> "${php_fpm_ini}"
echo "" >> "${php_fpm_ini}"
echo "; Specify user listener group" >> "${php_fpm_ini}"
echo "listen.group = users" >> "${php_fpm_ini}"

# config - rutorrent
####

rutorrent_plugins_path="/usr/share/webapps/rutorrent/plugins"

# set path to curl as rutorrent doesnt seem to find it on the path statement
sed -i -r "s~\"curl\"\s+=>\s+'',~\"curl\"   => '/usr/bin/curl',~g" "/etc/webapps/rutorrent/conf/config.php"

# increase rpc timeout from 5 seconds (default) for rutorrent, as large number of torrents can mean we exceed the 5 second period
sed -i -r "s~'RPC_TIME_OUT', [0-9]+,~'RPC_TIME_OUT', 60,~g" "/etc/webapps/rutorrent/conf/config.php"

# set the rutorrent autotools/autowatch plugin to 30 secs scan time, default is 300 secs
sed -i -e "s~\$autowatch_interval \= 300\;~\$autowatch_interval \= 30\;~g" "${rutorrent_plugins_path}/autotools/conf.php"

# set the rutorrent schedulder plugin to 10 mins, default is 60 mins
sed -i -e "s~\$updateInterval \= 60\;~\$updateInterval \= 10\;~g" "${rutorrent_plugins_path}/scheduler/conf.php"

# set the rutorrent diskspace plugin to point at the /data volume mapping, default is /
sed -i -e "s~\$partitionDirectory \= \&\$topDirectory\;~\$partitionDirectory \= \"/data\";~g" "${rutorrent_plugins_path}/diskspace/conf.php"

# config - autodl-irssi
####

# copy default configuration file
cp "/usr/share/webapps/rutorrent/plugins/autodl-irssi/_conf.php" "${rutorrent_plugins_path}/autodl-irssi/conf.php"

# set config for autodl-irssi plugin
sed -i -e 's~^$autodlPort.*~$autodlPort = 12345;~g' "${rutorrent_plugins_path}/autodl-irssi/conf.php"
sed -i -e 's~^$autodlPassword.*~$autodlPassword = "autodl-irssi";~g' "${rutorrent_plugins_path}/autodl-irssi/conf.php"

# set config for autodl (must match port and password specified in /usr/share/webapps/rutorrent/plugins/autodl-irssi/conf.php)
mkdir -p /home/nobody/.autodl
cat <<'EOF' > /home/nobody/.autodl/autodl.cfg.bak
[options]
gui-server-port = 12345
gui-server-password = autodl-irssi
EOF

# add in option to enable/disable autodl-irssi plugin depending on env var
# ENABLE_AUTODL_IRSSI value which is set when /home/nobody/irssi.sh runs
cat <<'EOF' >> "/etc/webapps/rutorrent/conf/plugins.ini"

[autodl-irssi]
enabled = no
EOF

# create symlink to autodl script so it auto runs when irssi (irc chat client) starts
mkdir -p /home/nobody/.irssi/scripts/autorun
cd /home/nobody/.irssi/scripts
ln -s /usr/share/autodl-irssi/AutodlIrssi/ .
cd /home/nobody/.irssi/scripts/autorun
ln -s /usr/share/autodl-irssi/autodl-irssi.pl .

# config - flood
####

flood_install_path="/etc/webapps/flood"

# copy config template file
cp "${flood_install_path}/config.template.js" "${flood_install_path}/config-backup.js"

# modify template with connection details to rtorrent
sed -i "s~host:.*~host: '127.0.0.1',~g" "${flood_install_path}/config-backup.js"

# point key and cert at nginx (note ssl not enabled by default)
sed -i "s~sslKey:.*~sslKey: '/config/nginx/certs/host.key',~g" "${flood_install_path}/config-backup.js"
sed -i "s~sslCert:.*~sslCert: '/config/nginx/certs/host.cert',~g" "${flood_install_path}/config-backup.js"

# set location of database (stores settings and user accounts)
sed -i "s~dbPath:.*~dbPath: '/config/flood/db/',~g" "${flood_install_path}/config-backup.js"

# set ip of host (talk on all ip's)
sed -i "s~floodServerHost.*~floodServerHost: '0.0.0.0',~g" "${flood_install_path}/config-backup.js"

# run npm build -  note we need to do this at this point as we need to have the modified config.js available for the build
cp -f "${flood_install_path}/config-backup.js" "${flood_install_path}/config.js"
cd "${flood_install_path}" && npm run build

# container perms
####

# define comma separated list of paths 
install_paths="/etc/webapps,/usr/share/webapps,/usr/share/nginx/html,/etc/nginx,/etc/php,/run/php-fpm,/var/lib/nginx,/var/log/nginx,/etc/privoxy,/home/nobody,/etc/webapps/flood,/usr/share/autodl-irssi"

# split comma separated string into list for install paths
IFS=',' read -ra install_paths_list <<< "${install_paths}"

# process install paths in the list
for i in "${install_paths_list[@]}"; do

	# confirm path(s) exist, if not then exit
	if [[ ! -d "${i}" ]]; then
		echo "[crit] Path '${i}' does not exist, exiting build process..." ; exit 1
	fi

done

# convert comma separated string of install paths to space separated, required for chmod/chown processing
install_paths=$(echo "${install_paths}" | tr ',' ' ')

# set permissions for container during build - Do NOT double quote variable for install_paths otherwise this will wrap space separated paths as a single string
chmod -R 775 ${install_paths}

# create file with contents of here doc, note EOF is NOT quoted to allow us to expand current variable 'install_paths'
# we use escaping to prevent variable expansion for PUID and PGID, as we want these expanded at runtime of init.sh
cat <<EOF > /tmp/permissions_heredoc

# get previous puid/pgid (if first run then will be empty string)
previous_puid=\$(cat "/tmp/puid" 2>/dev/null || true)
previous_pgid=\$(cat "/tmp/pgid" 2>/dev/null || true)

# if first run (no puid or pgid files in /tmp) or the PUID or PGID env vars are different 
# from the previous run then re-apply chown with current PUID and PGID values.
if [[ ! -f "/tmp/puid" || ! -f "/tmp/pgid" || "\${previous_puid}" != "\${PUID}" || "\${previous_pgid}" != "\${PGID}" ]]; then

	# set permissions inside container - Do NOT double quote variable for install_paths otherwise this will wrap space separated paths as a single string
	chown -R "\${PUID}":"\${PGID}" ${install_paths}

fi

# write out current PUID and PGID to files in /tmp (used to compare on next run)
echo "\${PUID}" > /tmp/puid
echo "\${PGID}" > /tmp/pgid

EOF

# replace permissions placeholder string with contents of file (here doc)
sed -i '/# PERMISSIONS_PLACEHOLDER/{
    s/# PERMISSIONS_PLACEHOLDER//g
    r /tmp/permissions_heredoc
}' /root/init.sh
rm /tmp/permissions_heredoc

# env vars
####

cat <<'EOF' > /tmp/envvars_heredoc

# check for presence of network interface docker0
check_network=$(ifconfig | grep docker0 || true)

# if network interface docker0 is present then we are running in host mode and thus must exit
if [[ ! -z "${check_network}" ]]; then
	echo "[crit] Network type detected as 'Host', this will cause major issues, please stop the container and switch back to 'Bridge' mode" | ts '%Y-%m-%d %H:%M:%.S' && exit 1
fi

export VPN_ENABLED=$(echo "${VPN_ENABLED}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
if [[ ! -z "${VPN_ENABLED}" ]]; then
	if [ "${VPN_ENABLED}" != "no" ] && [ "${VPN_ENABLED}" != "No" ] && [ "${VPN_ENABLED}" != "NO" ]; then
		export VPN_ENABLED="yes"
		echo "[info] VPN_ENABLED defined as '${VPN_ENABLED}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		export VPN_ENABLED="no"
		echo "[info] VPN_ENABLED defined as '${VPN_ENABLED}'" | ts '%Y-%m-%d %H:%M:%.S'
		echo "[warn] !!IMPORTANT!! VPN IS SET TO DISABLED', YOU WILL NOT BE SECURE" | ts '%Y-%m-%d %H:%M:%.S'
	fi
else
	echo "[warn] VPN_ENABLED not defined,(via -e VPN_ENABLED), defaulting to 'yes'" | ts '%Y-%m-%d %H:%M:%.S'
	export VPN_ENABLED="yes"
fi

if [[ $VPN_ENABLED == "yes" ]]; then

	# create directory to store openvpn config files
	mkdir -p /config/openvpn

	# set perms and owner for files in /config/openvpn directory
	set +e
	chown -R "${PUID}":"${PGID}" "/config/openvpn" &> /dev/null
	exit_code_chown=$?
	chmod -R 775 "/config/openvpn" &> /dev/null
	exit_code_chmod=$?
	set -e

	if (( ${exit_code_chown} != 0 || ${exit_code_chmod} != 0 )); then
		echo "[warn] Unable to chown/chmod /config/openvpn/, assuming SMB mountpoint" | ts '%Y-%m-%d %H:%M:%.S'
	fi

	# force removal of mac os resource fork files in ovpn folder
	rm -rf /config/openvpn/._*.ovpn

	# wildcard search for openvpn config files (match on first result)
	export VPN_CONFIG=$(find /config/openvpn -maxdepth 1 -name "*.ovpn" -print -quit)

	# if ovpn file not found in /config/openvpn then exit
	if [[ -z "${VPN_CONFIG}" ]]; then
		echo "[crit] No OpenVPN config file located in /config/openvpn/ (ovpn extension), please download from your VPN provider and then restart this container, exiting..." | ts '%Y-%m-%d %H:%M:%.S' && exit 1
	fi

	echo "[info] OpenVPN config file (ovpn extension) is located at ${VPN_CONFIG}" | ts '%Y-%m-%d %H:%M:%.S'

	# convert CRLF (windows) to LF (unix) for ovpn
	/usr/bin/dos2unix "${VPN_CONFIG}" 1> /dev/null

	# get first matching 'remote' line in ovpn
	vpn_remote_line=$(cat "${VPN_CONFIG}" | grep -P -o -m 1 '^(\s+)?remote\s.*')

	if [ -n "${vpn_remote_line}" ]; then

		# remove all remote lines as we cannot cope with multi remote lines
		sed -i -E '/^(\s+)?remote\s.*/d' "${VPN_CONFIG}"

		# if remote line contains comments then remove
		vpn_remote_line=$(echo "${vpn_remote_line}" | sed -r 's~\s?+#.*$~~g')

		# if remote line contains old format 'tcp' then replace with newer 'tcp-client' format
		vpn_remote_line=$(echo "${vpn_remote_line}" | sed "s/tcp$/tcp-client/g")

		# write the single remote line back to the ovpn file on line 1
		sed -i -e "1i${vpn_remote_line}" "${VPN_CONFIG}"

		echo "[info] VPN remote line defined as '${vpn_remote_line}'" | ts '%Y-%m-%d %H:%M:%.S'

	else

		echo "[crit] VPN configuration file ${VPN_CONFIG} does not contain 'remote' line, showing contents of file before exit..." | ts '%Y-%m-%d %H:%M:%.S'
		cat "${VPN_CONFIG}" && exit 1

	fi

	export VPN_REMOTE=$(echo "${vpn_remote_line}" | grep -P -o -m 1 '(?<=remote\s)[^\s]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${VPN_REMOTE}" ]]; then
		echo "[info] VPN_REMOTE defined as '${VPN_REMOTE}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[crit] VPN_REMOTE not found in ${VPN_CONFIG}, exiting..." | ts '%Y-%m-%d %H:%M:%.S' && exit 1
	fi

	export VPN_PORT=$(echo "${vpn_remote_line}" | grep -P -o -m 1 '\d{2,5}(\s?)+(tcp|udp|tcp-client)?$' | grep -P -o -m 1 '\d+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${VPN_PORT}" ]]; then
		echo "[info] VPN_PORT defined as '${VPN_PORT}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[crit] VPN_PORT not found in ${VPN_CONFIG}, exiting..." | ts '%Y-%m-%d %H:%M:%.S' && exit 1
	fi

	# if 'proto' is old format 'tcp' then forcibly set to newer 'tcp-client' format
	sed -i "s/^proto\stcp$/proto tcp-client/g" "${VPN_CONFIG}"

	export VPN_PROTOCOL=$(cat "${VPN_CONFIG}" | grep -P -o -m 1 '(?<=^proto\s)[^\r\n]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${VPN_PROTOCOL}" ]]; then
		echo "[info] VPN_PROTOCOL defined as '${VPN_PROTOCOL}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		export VPN_PROTOCOL=$(echo "${vpn_remote_line}" | grep -P -o -m 1 'udp|tcp-client|tcp$' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
		if [[ ! -z "${VPN_PROTOCOL}" ]]; then
			echo "[info] VPN_PROTOCOL defined as '${VPN_PROTOCOL}'" | ts '%Y-%m-%d %H:%M:%.S'
		else
			echo "[warn] VPN_PROTOCOL not found in ${VPN_CONFIG}, assuming udp" | ts '%Y-%m-%d %H:%M:%.S'
			export VPN_PROTOCOL="udp"
		fi
	fi

	VPN_DEVICE_TYPE=$(cat "${VPN_CONFIG}" | grep -P -o -m 1 '(?<=^dev\s)[^\r\n\d]+' | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${VPN_DEVICE_TYPE}" ]]; then
		export VPN_DEVICE_TYPE="${VPN_DEVICE_TYPE}0"
		echo "[info] VPN_DEVICE_TYPE defined as '${VPN_DEVICE_TYPE}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[crit] VPN_DEVICE_TYPE not found in ${VPN_CONFIG}, exiting..." | ts '%Y-%m-%d %H:%M:%.S' && exit 1
	fi

	# get values from env vars as defined by user
	export VPN_PROV=$(echo "${VPN_PROV}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${VPN_PROV}" ]]; then
		echo "[info] VPN_PROV defined as '${VPN_PROV}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[crit] VPN_PROV not defined,(via -e VPN_PROV), exiting..." | ts '%Y-%m-%d %H:%M:%.S' && exit 1
	fi

	export LAN_NETWORK=$(echo "${LAN_NETWORK}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${LAN_NETWORK}" ]]; then
		echo "[info] LAN_NETWORK defined as '${LAN_NETWORK}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[crit] LAN_NETWORK not defined (via -e LAN_NETWORK), exiting..." | ts '%Y-%m-%d %H:%M:%.S' && exit 1
	fi

	export NAME_SERVERS=$(echo "${NAME_SERVERS}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${NAME_SERVERS}" ]]; then
		echo "[info] NAME_SERVERS defined as '${NAME_SERVERS}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[warn] NAME_SERVERS not defined (via -e NAME_SERVERS), defaulting to Google and FreeDNS name servers" | ts '%Y-%m-%d %H:%M:%.S'
		export NAME_SERVERS="8.8.8.8,37.235.1.174,8.8.4.4,37.235.1.177"
	fi

	if [[ $VPN_PROV != "airvpn" ]]; then
		export VPN_USER=$(echo "${VPN_USER}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
		if [[ ! -z "${VPN_USER}" ]]; then
			echo "[info] VPN_USER defined as '${VPN_USER}'" | ts '%Y-%m-%d %H:%M:%.S'
		else
			echo "[warn] VPN_USER not defined (via -e VPN_USER), assuming authentication via other method" | ts '%Y-%m-%d %H:%M:%.S'
		fi

		export VPN_PASS=$(echo "${VPN_PASS}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
		if [[ ! -z "${VPN_PASS}" ]]; then
			echo "[info] VPN_PASS defined as '${VPN_PASS}'" | ts '%Y-%m-%d %H:%M:%.S'
		else
			echo "[warn] VPN_PASS not defined (via -e VPN_PASS), assuming authentication via other method" | ts '%Y-%m-%d %H:%M:%.S'
		fi
	fi

	export VPN_OPTIONS=$(echo "${VPN_OPTIONS}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${VPN_OPTIONS}" ]]; then
		echo "[info] VPN_OPTIONS defined as '${VPN_OPTIONS}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[info] VPN_OPTIONS not defined (via -e VPN_OPTIONS)" | ts '%Y-%m-%d %H:%M:%.S'
		export VPN_OPTIONS=""
	fi

	if [[ $VPN_PROV == "pia" ]]; then

		export STRICT_PORT_FORWARD=$(echo "${STRICT_PORT_FORWARD}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
		if [[ ! -z "${STRICT_PORT_FORWARD}" ]]; then
			echo "[info] STRICT_PORT_FORWARD defined as '${STRICT_PORT_FORWARD}'" | ts '%Y-%m-%d %H:%M:%.S'
		else
			echo "[warn] STRICT_PORT_FORWARD not defined (via -e STRICT_PORT_FORWARD), defaulting to 'yes'" | ts '%Y-%m-%d %H:%M:%.S'
			export STRICT_PORT_FORWARD="yes"
		fi

	fi

	export ENABLE_PRIVOXY=$(echo "${ENABLE_PRIVOXY}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
	if [[ ! -z "${ENABLE_PRIVOXY}" ]]; then
		echo "[info] ENABLE_PRIVOXY defined as '${ENABLE_PRIVOXY}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[warn] ENABLE_PRIVOXY not defined (via -e ENABLE_PRIVOXY), defaulting to 'no'" | ts '%Y-%m-%d %H:%M:%.S'
		export ENABLE_PRIVOXY="no"
	fi

	export RUN_UP_SCRIPT="yes"

fi

export ENABLE_FLOOD=$(echo "${ENABLE_FLOOD}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
if [[ ! -z "${ENABLE_FLOOD}" ]]; then
	echo "[info] ENABLE_FLOOD defined as '${ENABLE_FLOOD}'" | ts '%Y-%m-%d %H:%M:%.S'
else
	echo "[warn] ENABLE_FLOOD not defined (via -e ENABLE_FLOOD), defaulting to 'no'" | ts '%Y-%m-%d %H:%M:%.S'
	export ENABLE_FLOOD="no"
fi

export ENABLE_AUTODL_IRSSI=$(echo "${ENABLE_AUTODL_IRSSI}" | sed -e 's~^[ \t]*~~;s~[ \t]*$~~')
if [[ ! -z "${ENABLE_AUTODL_IRSSI}" ]]; then
	echo "[info] ENABLE_AUTODL_IRSSI defined as '${ENABLE_AUTODL_IRSSI}'" | ts '%Y-%m-%d %H:%M:%.S'
else
	echo "[warn] ENABLE_AUTODL_IRSSI not defined (via -e ENABLE_AUTODL_IRSSI), defaulting to 'no'" | ts '%Y-%m-%d %H:%M:%.S'
	export ENABLE_AUTODL_IRSSI="no"
fi

EOF

# replace env vars placeholder string with contents of file (here doc)
sed -i '/# ENVVARS_PLACEHOLDER/{
    s/# ENVVARS_PLACEHOLDER//g
    r /tmp/envvars_heredoc
}' /root/init.sh
rm /tmp/envvars_heredoc

# cleanup
yes|pacman -Scc
rm -rf /usr/share/locale/*
rm -rf /usr/share/man/*
rm -rf /usr/share/gtk-doc/*
rm -rf /tmp/*
