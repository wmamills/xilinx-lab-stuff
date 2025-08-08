all: boot.scr mod-kv260-prodsom.dtb

boot.scr: boot.script
	mkimage -c none -A arm64 -T script -d boot.script boot.scr

mod-kv260-prodsom.dtb: mod-kv260-prodsom.dts
	dtc -I dts -O dtb -o mod-kv260-prodsom.dtb mod-kv260-prodsom.dts
