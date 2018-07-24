#!/bin/bash

# if flood enabled then run, else log
if [[ "${ENABLE_FLOOD}" == "yes" || "${ENABLE_FLOOD}" == "both" ]]; then

	echo "[info] Flood enabled, waiting for rTorrent to start..."

	# wait for rtorrent process to start (listen for port)
	while [[ $(netstat -lnt | awk '$6 == "LISTEN" && $4 ~ ".5000"') == "" ]]; do
		sleep 0.1
	done

	echo "[info] rTorrent started, configuring Flood..."

	# if flood config file doesnt exist then copy from containr to /config, and back again to capture user changes (cannot soft link thus copy back)
	flood_config_path="/config/flood/config"
	flood_install_path="/etc/webapps/flood"

	if [ ! -f "${flood_config_path}/config.js" ]; then

		echo "[info] Flood config file ${flood_config_path}/config.js doesnt exist, copying from container..."
		mkdir -p "${flood_config_path}/"
		cp -f "${flood_install_path}/config-backup.js" "${flood_config_path}/config.js"

	fi

	echo "[info] Copying Flood config file ${flood_config_path}/config.js back to container..."
	mkdir -p "${flood_install_path}/"
	cp -f "${flood_config_path}/config.js" "${flood_install_path}/config.js"

	echo "[info] Starting Flood..."

	# run tmux attached to flood (non daemonized, blocking)
	# cd "${flood_install_path}" && /usr/bin/script /home/nobody/typescript --command "/usr/bin/tmux new-session -s flood -n flood npm run start:production" &>/dev/null
	# run flood with forever
	cd "${flood_install_path}" && /usr/bin/script /home/nobody/typescript --command "forever start -c 'npm start' ."
else

	echo "[info] Flood not enabled, skipping starting Flood Web UI"

fi
