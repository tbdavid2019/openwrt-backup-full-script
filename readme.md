##  這是什麼？

該項目可以輕鬆備份iStoreOS已安裝的軟體和組態,當系統恢復出廠設定或重設後，可以一鍵恢復原來的軟體和組態。

改自 https://github.com/wukongdaily/OpenBackRestore/tree/master


## 舉例說明 

假設要備份到 /mnt/sata1-4目錄

執行備份

``
 sh backup.run /mnt/sata1-4' 
``


執行復原

``
 sh restore.run
``

---
## 如何使用？

- 開啟 cli 介面

- 無腦生成備份在 /tmp folder 中

``
wget -O backup.run https://github.com/tbdavid2019/openwrt-backup-full-script/raw/main/backup.run && sh backup.run
``

- 無腦恢復 
準備好 復原檔案 上傳到 /tmp folder 中

![alt text](image.png)

先下載 sh 
``
wget -O restore.run https://github.com/tbdavid2019/openwrt-backup-full-script/raw/main/restore.run
``

執行 
``
restore.run
``

