# figure out the boot script to use
set boot_script "boot-mmc.scr"

if { $argc >= 1 } {
    set boot_script [lindex $argv 0]
}

puts "boot_script=$boot_script"

# connect if not already
connect

# POR versal.
puts "# Reset Versal"
target 1
rst -por

# Give it 1.5s to settle
after 1500

puts "# Program boot.bin"
# Now load boot.bin
#device program boot.bin-svai-org
#device program boot.bin-brian
device program boot.bin-edgar

# Stop the A-cores
targets -set -nocase -filter {name =~ "*A72*#0"}
stop

puts "# Load system.dtb and boot.scr"
# Pre-populate device-tree and boot script.
targets -set -nocase -filter {name =~ "*Versal*"}
dow -data -force $boot_script 0x2100000
dow -data -force system-brian.dtb 0x20A00000

puts "# Release A-cores"
# Let the A cores boot.
targets -set -nocase -filter {name =~ "*A72*#0"}
con

puts "# if no auto boot, In u-boot prompt run:"
puts "source 0x2100000"

exit

