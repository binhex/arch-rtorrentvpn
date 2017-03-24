#!/bin/bash

# exit script if return code != 0
set -e

# build scripts
####

# download build scripts from github
curl -o /tmp/scripts-master.zip -L https://github.com/binhex/scripts/archive/master.zip

# unzip build scripts
unzip /tmp/scripts-master.zip -d /tmp

# move shell scripts to /root
find /tmp/scripts-master/ -type f -name '*.sh' -exec mv -i {} /root/  \;

# pacman packages
####

# define pacman packages
pacman_packages="git nginx php-fpm rsync openssl tmux gnu-netcat mediainfo npm nodejs php-geoip unzip unrar"

# install compiled packages using pacman
if [[ ! -z "${pacman_packages}" ]]; then
	pacman -S --needed $pacman_packages --noconfirm
fi

# aor packages
####

# define arch official repo (aor) packages
aor_packages="rtorrent"

# call aor script (arch official repo)
source /root/aor.sh

# aur packages
####

# define aur packages
aur_packages="rutorrent apache-tools"

# call aur install script (arch user repo)
source /root/aur.sh

# call custom install script
source /root/custom.sh

# config - php
####

# configure php memory limit to improve performance
sed -i -e "s~.*memory_limit\s\=\s.*~memory_limit = 512M~g" "/etc/php/php.ini"

# configure php max execution time to try and prevent timeout issues
sed -i -e "s~.*max_execution_time\s\=\s.*~max_execution_time = 300~g" "/etc/php/php.ini"

# configure php max file uploads to prevent issues with reaching limit of upload count
sed -i -e "s~.*max_file_uploads\s\=\s.*~max_file_uploads = 200~g" "/etc/php/php.ini"

# configure php max input variables (get/post/cookies) to prevent warnings issued
sed -i -e "s~.*max_input_vars\s\=\s.*~max_input_vars = 10000~g" "/etc/php/php.ini"

# configure php upload max filesize to prevent large torrent files failing to upload
sed -i -e "s~.*upload_max_filesize\s\=\s.*~upload_max_filesize = 20M~g" "/etc/php/php.ini"

# configure php post max size (linked to upload max filesize)
sed -i -e "s~.*post_max_size\s\=\s.*~post_max_size = 25M~g" "/etc/php/php.ini"

# configure php with additional php-geoip module
sed -i -e "/.*extension=gd.so/a extension=geoip.so" "/etc/php/php.ini"

# configure php-fpm to use tcp/ip connection for listener
echo "" >> /etc/php/php-fpm.conf
echo "; Set php-fpm to use tcp/ip connection" >> /etc/php/php-fpm.conf
echo "listen = 127.0.0.1:7777" >> /etc/php/php-fpm.conf

# configure php-fpm listener for user nobody, group users
echo "" >> /etc/php/php-fpm.conf
echo "; Specify user listener owner" >> /etc/php/php-fpm.conf
echo "listen.owner = nobody" >> /etc/php/php-fpm.conf
echo "" >> /etc/php/php-fpm.conf
echo "; Specify user listener group" >> /etc/php/php-fpm.conf
echo "listen.group = users" >> /etc/php/php-fpm.conf

# config - rutorrent
####

# set path to curl as rutorrent doesnt seem to find it on the path statement
sed -i -e "s~\"curl\"[[:space:]]\+\=>[[:space:]]\+'',~\"curl\"   \=> \'/usr/bin/curl\'\,~g" "/etc/webapps/rutorrent/conf/config.php"

# set the rutorrent autotools/autowatch plugin to 30 secs scan time, default is 300 secs
sed -i -e "s~\$autowatch_interval \= 300\;~\$autowatch_interval \= 30\;~g" "/usr/share/webapps/rutorrent/plugins/autotools/conf.php"

# set the rutorrent schedulder plugin to 10 mins, default is 60 mins
sed -i -e "s~\$updateInterval \= 60\;~\$updateInterval \= 10\;~g" "/usr/share/webapps/rutorrent/plugins/scheduler/conf.php"

# set the rutorrent diskspace plugin to point at the /data volume mapping, default is /
sed -i -e "s~\$partitionDirectory \= \&\$topDirectory\;~\$partitionDirectory \= \"/data\";~g" "/usr/share/webapps/rutorrent/plugins/diskspace/conf.php"

# delete rutorrent tracklabels plugin (causes error messages and crashes rtorrent) and screenshots plugin (not required on headless system)
rm -rf "/usr/share/webapps/rutorrent/plugins/tracklabels" "/usr/share/webapps/rutorrent/plugins/screenshots"

# config - flood
####

# copy config template file
cp /etc/webapps/flood/config.template.js /etc/webapps/flood/config-backup.js

# modify template with connection details to rtorrent
sed -i "s~host: 'localhost'~host: '127.0.0.1'~g" /etc/webapps/flood/config-backup.js

# point key and cert at nginx (note ssl not enabled by default)
sed -i "s~sslKey: '/absolute/path/to/key/'~sslKey: '/config/nginx/certs/host.key'~g" /etc/webapps/flood/config-backup.js
sed -i "s~sslCert: '/absolute/path/to/certificate/'~sslCert: '/config/nginx/certs/host.cert'~g" /etc/webapps/flood/config-backup.js

# set location of database (stores settings and user accounts)
sed -i "s~dbPath: './server/db/'~dbPath: '/config/flood/db/'~g" /etc/webapps/flood/config-backup.js

# container perms
####

# create file with contets of here doc
 cat <<'EOF' > /tmp/permissions_heredoc
# set permissions inside container
chown -R "${PUID}":"${PGID}" /etc/webapps/ /usr/share/webapps/ /usr/share/nginx/html/ /etc/nginx/ /etc/php/ /run/php-fpm/ /var/lib/nginx/ /var/log/nginx/ /etc/privoxy/ /home/nobody/ /etc/webapps/flood
chmod -R 775 /etc/webapps/ /usr/share/webapps/ /usr/share/nginx/html/ /etc/nginx/ /etc/php/ /run/php-fpm/ /var/lib/nginx/ /var/log/nginx/ /etc/privoxy/ /home/nobody/ /etc/webapps/flood

# set shell for user nobody
chsh -s /bin/bash nobody

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

export VPN_ENABLED=$(echo "${VPN_ENABLED}" | sed -e 's/^[ \t]*//')
if [[ ! -z "${VPN_ENABLED}" ]]; then
	echo "[info] VPN_ENABLED defined as '${VPN_ENABLED}'" | ts '%Y-%m-%d %H:%M:%.S'
else
	echo "[warn] VPN_ENABLED not defined,(via -e VPN_ENABLED), defaulting to 'yes'" | ts '%Y-%m-%d %H:%M:%.S'
	export VPN_ENABLED="yes"
fi

if [[ $VPN_ENABLED == "yes" ]]; then
	export VPN_PROV=$(echo "${VPN_PROV}" | sed -e 's/^[ \t]*//')
	if [[ ! -z "${VPN_PROV}" ]]; then
		echo "[info] VPN_PROV defined as '${VPN_PROV}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[crit] VPN_PROV not defined,(via -e VPN_PROV), exiting..." | ts '%Y-%m-%d %H:%M:%.S' && exit 1
	fi

	export VPN_REMOTE=$(echo "${VPN_REMOTE}" | sed -e 's/^[ \t]*//')
	if [[ ! -z "${VPN_REMOTE}" ]]; then
		echo "[info] VPN_REMOTE defined as '${VPN_REMOTE}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[crit] VPN_REMOTE not defined (via -e VPN_REMOTE), exiting..." | ts '%Y-%m-%d %H:%M:%.S' && exit 1
	fi

	export VPN_PORT=$(echo "${VPN_PORT}" | sed -e 's/^[ \t]*//')
	if [[ ! -z "${VPN_PORT}" ]]; then
		echo "[info] VPN_PORT defined as '${VPN_PORT}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[crit] VPN_PORT not defined (via -e VPN_PORT), exiting..." | ts '%Y-%m-%d %H:%M:%.S' && exit 1
	fi

	export VPN_PROTOCOL=$(echo "${VPN_PROTOCOL}" | sed -e 's/^[ \t]*//')
	if [[ ! -z "${VPN_PROTOCOL}" ]]; then
		echo "[info] VPN_PROTOCOL defined as '${VPN_PROTOCOL}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[crit] VPN_PROTOCOL not defined (via -e VPN_PROTOCOL), exiting..." | ts '%Y-%m-%d %H:%M:%.S' && exit 1
	fi

	export LAN_NETWORK=$(echo "${LAN_NETWORK}" | sed -e 's/^[ \t]*//')
	if [[ ! -z "${LAN_NETWORK}" ]]; then
		echo "[info] LAN_NETWORK defined as '${LAN_NETWORK}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[crit] LAN_NETWORK not defined (via -e LAN_NETWORK), exiting..." | ts '%Y-%m-%d %H:%M:%.S' && exit 1
	fi

	export NAME_SERVERS=$(echo "${NAME_SERVERS}" | sed -e 's/^[ \t]*//')
	if [[ ! -z "${NAME_SERVERS}" ]]; then
		echo "[info] NAME_SERVERS defined as '${NAME_SERVERS}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[warn] NAME_SERVERS not defined (via -e NAME_SERVERS), defaulting to Google and FreeDNS name servers" | ts '%Y-%m-%d %H:%M:%.S'
		export NAME_SERVERS="8.8.8.8,37.235.1.174,8.8.4.4,37.235.1.177"
	fi

	if [[ $VPN_PROV != "airvpn" ]]; then
		export VPN_USER=$(echo "${VPN_USER}" | sed -e 's/^[ \t]*//')
		if [[ ! -z "${VPN_USER}" ]]; then
			echo "[info] VPN_USER defined as '${VPN_USER}'" | ts '%Y-%m-%d %H:%M:%.S'
		else
			echo "[warn] VPN_USER not defined (via -e VPN_USER), assuming authentication via other method" | ts '%Y-%m-%d %H:%M:%.S'
		fi

		export VPN_PASS=$(echo "${VPN_PASS}" | sed -e 's/^[ \t]*//')
		if [[ ! -z "${VPN_PASS}" ]]; then
			echo "[info] VPN_PASS defined as '${VPN_PASS}'" | ts '%Y-%m-%d %H:%M:%.S'
		else
			echo "[warn] VPN_PASS not defined (via -e VPN_PASS), assuming authentication via other method" | ts '%Y-%m-%d %H:%M:%.S'
		fi
	fi

	export VPN_INCOMING_PORT=$(echo "${VPN_INCOMING_PORT}" | sed -e 's/^[ \t]*//')
	if [[ ! -z "${VPN_INCOMING_PORT}" ]]; then
		echo "[info] VPN_INCOMING_PORT defined as '${VPN_INCOMING_PORT}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[warn] VPN_INCOMING_PORT not defined (via -e VPN_INCOMING_PORT), downloads may be slow" | ts '%Y-%m-%d %H:%M:%.S'
		export VPN_INCOMING_PORT=""
	fi

	export VPN_DEVICE_TYPE=$(echo "${VPN_DEVICE_TYPE}" | sed -e 's/^[ \t]*//')
	if [[ ! -z "${VPN_DEVICE_TYPE}" ]]; then
		echo "[info] VPN_DEVICE_TYPE defined as '${VPN_DEVICE_TYPE}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[warn] VPN_DEVICE_TYPE not defined (via -e VPN_DEVICE_TYPE), defaulting to 'tun'" | ts '%Y-%m-%d %H:%M:%.S'
		export VPN_DEVICE_TYPE="tun"
	fi

	export VPN_OPTIONS=$(echo "${VPN_OPTIONS}" | sed -e 's/^[ \t]*//')
	if [[ ! -z "${VPN_OPTIONS}" ]]; then
		echo "[info] VPN_OPTIONS defined as '${VPN_OPTIONS}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[info] VPN_OPTIONS not defined (via -e VPN_OPTIONS)" | ts '%Y-%m-%d %H:%M:%.S'
		export VPN_OPTIONS=""
	fi

	if [[ $VPN_PROV == "pia" ]]; then
		export STRONG_CERTS=$(echo "${STRONG_CERTS}" | sed -e 's/^[ \t]*//')
		if [[ ! -z "${STRONG_CERTS}" ]]; then
			echo "[info] STRONG_CERTS defined as '${STRONG_CERTS}'" | ts '%Y-%m-%d %H:%M:%.S'
		else
			echo "[warn] STRONG_CERTS not defined (via -e STRONG_CERTS), defaulting to 'no'" | ts '%Y-%m-%d %H:%M:%.S'
			export STRONG_CERTS="no"
		fi
	fi

	export ENABLE_PRIVOXY=$(echo "${ENABLE_PRIVOXY}" | sed -e 's/^[ \t]*//')
	if [[ ! -z "${ENABLE_PRIVOXY}" ]]; then
		echo "[info] ENABLE_PRIVOXY defined as '${ENABLE_PRIVOXY}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[warn] ENABLE_PRIVOXY not defined (via -e ENABLE_PRIVOXY), defaulting to 'no'" | ts '%Y-%m-%d %H:%M:%.S'
		export ENABLE_PRIVOXY="no"
	fi

	export ENABLE_FLOOD=$(echo "${ENABLE_FLOOD}" | sed -e 's/^[ \t]*//')
	if [[ ! -z "${ENABLE_FLOOD}" ]]; then
		echo "[info] ENABLE_FLOOD defined as '${ENABLE_FLOOD}'" | ts '%Y-%m-%d %H:%M:%.S'
	else
		echo "[warn] ENABLE_FLOOD not defined (via -e ENABLE_FLOOD), defaulting to 'no'" | ts '%Y-%m-%d %H:%M:%.S'
		export ENABLE_FLOOD="no"
	fi
	
elif [[ $VPN_ENABLED == "no" ]]; then
	echo "[warn] !!IMPORTANT!! You have set the VPN to disabled, you will NOT be secure!" | ts '%Y-%m-%d %H:%M:%.S'
fi

EOF

# replace permissions placeholder string with contents of file (here doc)
sed -i '/# ENVVARS_PLACEHOLDER/{
    s/# ENVVARS_PLACEHOLDER//g
    r /tmp/envvars_heredoc
}' /root/init.sh
rm /tmp/envvars_heredoc

# cleanup
yes|pacman -Scc
rm -rf /usr/share/locale/*
rm -rf /usr/share/man/*
rm -rf /tmp/*
