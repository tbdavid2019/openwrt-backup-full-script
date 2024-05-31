#!/bin/sh
# 定義顏色輸出函數
red() { echo -e "\033[31m\033[01m[WARNING] $1\033[0m"; }
green() { echo -e "\033[32m\033[01m[INFO] $1\033[0m"; }
yellow() { echo -e "\033[33m\033[01m[NOTICE] $1\033[0m"; }
blue() { echo -e "\033[34m\033[01m[MESSAGE] $1\033[0m"; }
light_magenta() { echo -e "\033[95m\033[01m[NOTICE] $1\033[0m"; }
light_yellow() { echo -e "\033[93m\033[01m[NOTICE] $1\033[0m"; }

third_party_source="https://istore.linkease.com/repo/all/nas_luci"
base_address="https://gitee.com/wukongdaily/gl_onescript/raw/master"
do_docker_shell=$base_address/docker/do_docker.sh
setup_base_init() {

	#新增出處資訊
	add_author_info
	#新增Android時間伺服器
	add_dhcp_domain
    # 設定時區為台灣
    uci set system.@system[0].zonename='Asia/Taipei'
    uci set system.@system[0].timezone='CST-8'
    uci commit system
    /etc/init.d/system reload

	## 設定防火牆wan 打開,方便主路由訪問
	uci set firewall.@zone[1].input='ACCEPT'
	uci commit firewall

}

## 安裝應用程式商店和主題
install_istore_os_style() {
	##設定Argon 紫色主題
	do_install_argon_skin
	#增加首頁終端圖示
	opkg install ttyd
	#默認使用體積很小的檔案傳輸：系統——檔案傳輸
	do_install_filetransfer
	#默認安裝必備工具SFTP 方便下載檔案 比如finalshell等工具可以直接瀏覽路由器檔案
	is-opkg install app-meta-sftp
	is-opkg install 'app-meta-ddnsto'
	# 安裝磁碟管理
	is-opkg install 'app-meta-diskman'
	# 若已安裝iStore商店則在概覽中追加iStore字樣
	if ! grep -q " like iStoreOS" /tmp/sysinfo/model; then
		sed -i '1s/$/ like iStoreOS/' /tmp/sysinfo/model
	fi
}
# 安裝iStore 參考 https://github.com/linkease/istore
do_istore() {
	echo "do_istore method==================>"
	ISTORE_REPO=https://istore.linkease.com/repo/all/store
	FCURL="curl --fail --show-error"

	curl -V >/dev/null 2>&1 || {
		echo "prereq: install curl"
		opkg info curl | grep -Fqm1 curl || opkg update
		opkg install curl
	}

	IPK=$($FCURL "$ISTORE_REPO/Packages.gz" | zcat | grep -m1 '^Filename: luci-app-store.*\.ipk$' | sed -n -e 's/^Filename: \(.\+\)$/\1/p')

	[ -n "$IPK" ] || exit 1

	$FCURL "$ISTORE_REPO/$IPK" | tar -xzO ./data.tar.gz | tar -xzO ./bin/is-opkg >/tmp/is-opkg

	[ -s "/tmp/is-opkg" ] || exit 1

	chmod 755 /tmp/is-opkg
	/tmp/is-opkg update
	# /tmp/is-opkg install taskd
	/tmp/is-opkg opkg install --force-reinstall luci-lib-taskd luci-lib-xterm
	/tmp/is-opkg opkg install --force-reinstall luci-app-store || exit $?
	[ -s "/etc/init.d/tasks" ] || /tmp/is-opkg opkg install --force-reinstall taskd
	[ -s "/usr/lib/lua/luci/cbi.lua" ] || /tmp/is-opkg opkg install luci-compat >/dev/null 2>&1
}

#設定風扇工作溫度
setup_cpu_fans() {
	#設定溫度閥值,cpu高於48度,則風搧開始工作
	uci set glfan.@globals[0].temperature=48
	uci set glfan.@globals[0].warn_temperature=48
	uci set glfan.@globals[0].integration=4
	uci set glfan.@globals[0].differential=20
	uci commit glfan
	/etc/init.d/gl_fan restart
}

# 判斷系統是否為iStoreOS
is_iStoreOS() {
	DISTRIB_ID=$(cat /etc/openwrt_release | grep "DISTRIB_ID" | cut -d "'" -f 2)
	# 檢查DISTRIB_ID的值是否等於'iStoreOS'
	if [ "$DISTRIB_ID" = "iStoreOS" ]; then
		return 0 # true
	else
		return 1 # false
	fi
}

## 去除opkg簽名
remove_check_signature_option() {
	local opkg_conf="/etc/opkg.conf"
	sed -i '/option check_signature/d' "$opkg_conf"
}

## 新增opkg簽名
add_check_signature_option() {
	local opkg_conf="/etc/opkg.conf"
	echo "option check_signature 1" >>"$opkg_conf"
}

#設定第三方軟體源
setup_software_source() {
	## 傳入0和1 分別代表原始和第三方軟體源
	if [ "$1" -eq 0 ]; then
		echo "# add your custom package feeds here" >/etc/opkg/customfeeds.conf
		##如果是iStoreOS系統,還原軟體源之後，要新增簽名
		if is_iStoreOS; then
			add_check_signature_option
		else
			echo
		fi
		# 還原軟體源之後更新
		opkg update
	elif [ "$1" -eq 1 ]; then
		#傳入1 代表設定第三方軟體源 先要刪掉簽名
		remove_check_signature_option
		# 先刪除再新增以免重複
		echo "# add your custom package feeds here" >/etc/opkg/customfeeds.conf
		echo "src/gz third_party_source $third_party_source" >>/etc/opkg/customfeeds.conf
		# 設定第三方源後要更新
		opkg update
	else
		echo "Invalid option. Please provide 0 or 1."
	fi
}

# 新增主機名對應(解決Android原生TV首次連不上wifi的問題)
add_dhcp_domain() {
	local domain_name="time.android.com"
	local domain_ip="203.107.6.88"

	# 檢查是否存在相同的域名記錄
	existing_records=$(uci show dhcp | grep "dhcp.@domain\[[0-9]\+\].name='$domain_name'")
	if [ -z "$existing_records" ]; then
		# 新增新的域名記錄
		uci add dhcp domain
		uci set "dhcp.@domain[-1].name=$domain_name"
		uci set "dhcp.@domain[-1].ip=$domain_ip"
		uci commit dhcp
	else
		echo
	fi
}

#新增出處資訊
add_author_info() {
	uci set system.@system[0].description='wukongdaily'
	uci set system.@system[0].notes='文件說明:
    https://github.com/wukongdaily/gl-inet-onescript'
	uci commit system
}

##獲取軟路由型號資訊
get_router_name() {
	model_info=$(cat /tmp/sysinfo/model)
	echo "$model_info"
}

get_router_hostname() {
	hostname=$(uci get system.@system[0].hostname)
	echo "$hostname 路由器"
}

add_custom_feed() {
	# 先清空組態
	echo "# add your custom package feeds here" >/etc/opkg/customfeeds.conf
	# Prompt the user to enter the feed URL
	echo "請輸入自訂軟體源的地址(通常是https開頭 aarch64_cortex-a53 結尾):"
	read feed_url
	if [ -n "$feed_url" ]; then
		echo "src/gz custom_feed $feed_url" >>/etc/opkg/customfeeds.conf
		opkg update
		if [ $? -eq 0 ]; then
			echo "已新增並更新列表."
		else
			echo "已新增但更新失敗,請檢查網路或重試."
		fi
	else
		echo "Error: Feed URL not provided. No changes were made."
	fi
}

remove_custom_feed() {
	echo "# add your custom package feeds here" >/etc/opkg/customfeeds.conf
	opkg update
	if [ $? -eq 0 ]; then
		echo "已刪除並更新列表."
	else
		echo "已刪除了自訂軟體源但更新失敗,請檢查網路或重試."
	fi
}



# 執行重啟操作
do_reboot() {
	reboot
}

#提示使用者要重啟
show_reboot_tips() {
	reboot_code='do_reboot'
	show_whiptail_dialog "重啟提醒" "           $(get_router_hostname)\n           一鍵風格化運行完成.\n           為了更好的清理臨時快取,\n           您是否要重啟路由器?" "$reboot_code"
}

#自訂風搧開始工作的溫度
set_glfan_temp() {

	is_integer() {
		if [[ $1 =~ ^[0-9]+$ ]]; then
			return 0 # 是整數
		else
			return 1 # 不是整數
		fi
	}
	echo "相容帶風扇機型的GL-iNet路由器"
	echo "請輸入風搧開始工作的溫度(建議40-70之間的整數):"
	read temp

	if is_integer "$temp"; then
		uci set glfan.@globals[0].temperature="$temp"
		uci set glfan.@globals[0].warn_temperature="$temp"
		uci set glfan.@globals[0].integration=4
		uci set glfan.@globals[0].differential=20
		uci commit glfan
		/etc/init.d/gl_fan restart
		echo "設定成功！稍等片刻,請查看風扇轉動情況"
	else
		echo "錯誤: 請輸入整數."
	fi
}

recovery_opkg_settings() {
	echo "# add your custom package feeds here" >/etc/opkg/customfeeds.conf
	router_name=$(get_router_name)
	case "$router_name" in
	*3000*)
		echo "Router name contains '3000'."
		mt3000_opkg="https://gitee.com/wukongdaily/gl_onescript/raw/master/mt-3000/distfeeds.conf"
		wget -O /etc/opkg/distfeeds.conf ${mt3000_opkg}
		;;
	*2500*)
		echo "Router name contains '2500'."
		mt2500a_opkg="https://gitee.com/wukongdaily/gl_onescript/raw/master/mt-2500a/distfeeds.conf"
		wget -O /etc/opkg/distfeeds.conf ${mt2500a_opkg}
		;;
	*6000*)
		update_opkg_config
		;;
	*)
		echo "Router name does not contain '3000' 6000 or '2500'."
		;;
	esac
}

update_opkg_config() {
	kernel_version=$(uname -r)
	echo "MT-6000 kernel version: $kernel_version"
	case $kernel_version in
	5.4*)

		mt6000_opkg="https://gitee.com/wukongdaily/gl_onescript/raw/master/mt-6000/distfeeds-5.4.conf"
		wget -O /etc/opkg/distfeeds.conf ${mt6000_opkg}
		# 更換5.4.238 核心之後 缺少的依賴
		mkdir -p /tmp/mt6000
		wget -O /tmp/mt6000/script-utils.ipk "https://gitee.com/wukongdaily/gl_onescript/raw/master/mt-6000/script-utils.ipk"
		wget -O /tmp/mt6000/mdadm.ipk "https://gitee.com/wukongdaily/gl_onescript/raw/master/mt-6000/mdadm.ipk"
		wget -O /tmp/mt6000/lsblk.ipk "https://gitee.com/wukongdaily/gl_onescript/raw/master/mt-6000/lsblk.ipk"
		opkg update
		if [ -f "/tmp/mt6000/lsblk.ipk" ]; then
			# 先解除安裝之前安裝過的lsblk,確保使用的是正確的lsblk
			opkg remove lsblk
		fi
		opkg install /tmp/mt6000/*.ipk
		;;
	5.15*)
		mt6000_opkg="https://gitee.com/wukongdaily/gl_onescript/raw/master/mt-6000/distfeeds.conf"
		wget -O /etc/opkg/distfeeds.conf ${mt6000_opkg}
		;;
	*)
		echo "Unsupported kernel version: $kernel_version"
		return 1
		;;
	esac
}


update_luci_app_quickstart() {
	if [ -f "/bin/is-opkg" ]; then
		# 如果 /bin/is-opkg 存在，則執行 is-opkg update
		is-opkg update
		is-opkg install luci-i18n-quickstart-zh-cn --force-depends >/dev/null 2>&1
	else
		red "請先執行第一項 一鍵iStoreOS風格化"
	fi
}

# 安裝體積非常小的檔案傳輸軟體 默認上傳位置/tmp/upload/
do_install_filetransfer() {
	mkdir -p /tmp/luci-app-filetransfer/
	cd /tmp/luci-app-filetransfer/
	wget -O luci-app-filetransfer_all.ipk "https://gitee.com/wukongdaily/gl_onescript/raw/master/luci-app-filetransfer/luci-app-filetransfer_all.ipk"
	wget -O luci-lib-fs_1.0-14_all.ipk "https://gitee.com/wukongdaily/gl_onescript/raw/master/luci-app-filetransfer/luci-lib-fs_1.0-14_all.ipk"
	opkg install *.ipk --force-depends
}
do_install_depends_ipk() {
	wget -O "/tmp/luci-lua-runtime_all.ipk" "https://gitee.com/wukongdaily/gl_onescript/raw/master/theme/luci-lua-runtime_all.ipk"
	wget -O "/tmp/libopenssl3.ipk" "https://gitee.com/wukongdaily/gl_onescript/raw/master/theme/libopenssl3.ipk"
	opkg install "/tmp/luci-lua-runtime_all.ipk"
	opkg install "/tmp/libopenssl3.ipk"
}
#單獨安裝argon主題
do_install_argon_skin() {
	#下載和安裝argon的依賴
	do_install_depends_ipk
	# bug fix 由於2.3.1 最新版的luci-argon-theme 登錄按鈕沒有中文匹配,而2.3版本字型不對。
	# 所以這裡安裝上一個版本2.2.9,考慮到主題皮膚並不需要長期更新，因此固定版本沒問題
	opkg update
	opkg install luci-lib-ipkg
	wget -O "/tmp/luci-theme-argon.ipk" "https://gitee.com/wukongdaily/gl_onescript/raw/master/theme/luci-theme-argon-master_2.2.9.4_all.ipk"
	wget -O "/tmp/luci-app-argon-config.ipk" "https://gitee.com/wukongdaily/gl_onescript/raw/master/theme/luci-app-argon-config_0.9_all.ipk"
	wget -O "/tmp/luci-i18n-argon-config-zh-cn.ipk" "https://gitee.com/wukongdaily/gl_onescript/raw/master/theme/luci-i18n-argon-config-zh-cn.ipk"
	cd /tmp/
	opkg install luci-theme-argon.ipk luci-app-argon-config.ipk luci-i18n-argon-config-zh-cn.ipk
	# 檢查上一個命令的返回值
	if [ $? -eq 0 ]; then
		echo "argon主題 安裝成功"
		# 設定主題和語言
		uci set luci.main.mediaurlbase='/luci-static/argon'
		uci set luci.main.lang='zh_cn'
		uci commit
	else
		echo "argon主題 安裝失敗! 建議再執行一次!再給我一個機會!事不過三!"
	fi
}

#單獨安裝檔案管理器
do_install_filemanager() {
	echo "為避免bug,安裝檔案管理器之前,需要先iStore商店"
	do_istore
	echo "接下來 嘗試安裝檔案管理器......."
	is-opkg install 'app-meta-linkease'
	echo "重新登錄web頁面,然後您可以訪問:  http://192.168.8.1/cgi-bin/luci/admin/services/linkease/file/?path=/root"
}

restore() {
	gl_name=$(get_router_name)
	if [[ "$gl_name" == *3000* ]]; then
		# 設定風扇工作溫度
		setup_cpu_fans
	fi
	# 解決首頁“已聯網”的UI問題
	recovery_opkg_settings
	#先安裝istore商店
	do_istore
	#安裝iStore風格
	install_istore_os_style
	#安裝iStore首頁風格
	update_luci_app_quickstart
	#基礎必備設定
	setup_base_init
	green "已恢復iStoreOS風格,現在請將備份檔案 backup.tar.gz 上傳到/tmp/upload,然後再次執行sh restore.run"
}
restore