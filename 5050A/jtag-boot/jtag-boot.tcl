puts "# Reset Versal"
# POR versal.
target 1
rst -por

# Give it 1s to settle
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
#dow -data -force system.dtb 0x00001000
#dow -data -force boot.scr 0x20000000
dow -data -force boot.scr 0x2000000 

#dow -data -force system-brian.dtb 0x20A00000
dow -data -force system-brian.dtb 0x20A00000

puts "# Release A-cores"
# Let the A cores boot.
targets -set -nocase -filter {name =~ "*A72*#0"}
con

puts "# In u-boot prompt run:"
puts "source 0x2000000"

