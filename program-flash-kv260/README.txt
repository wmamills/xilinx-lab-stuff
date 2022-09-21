== program-flash-kv260 ==

This is a set of binaries and scripts that can be used to program a 
Kria Production SOM to make it work similar to a starter SOM.

* safe-test-kv260
** Safe to test on kv260 w/ starter SOM
** Use this to test the program_flash installation before switching to production SOMs
* write-som
** Full script to commission a production SOM’s QSPI to make it look like a kv260.
** Installs the image-selector and recovery app.
** Also writes initial Image A & B to be full BOOT.BIN from Xilinx

== program_flash ==

This set of scripts to program a Kria SOM.

These scripts use the program_flash program from the Xilinx tools.
At the time of writing this was using 2021.2 versions.
The program_flash program is not part of the lab edition.
It is only available in the Vitis tool set.

The Vitis tool set can take multiple hours to download and multiple hours to
install.

If you are a Linaro employee you can use a cutdown version that is 6GB and 
can be installed via un'taring it.  This can be found here:
https://drive.google.com/drive/folders/1NQRmOa2dFkG8tga7h4fbVX3rZi1CF-w1?usp=sharing

