# BUG: won't work when no one is watching

## Exec Summary
* Now works due to recovery using unique autoboot stop sequence "RR"
    - It also flushes the input before waiting for the key sequence
* Meta-TS firmware does not show the problem even under the same conditions
    - That firmware should soon disable "hit any key" anyway
* Root cause is still not understood and MIGHT come back to bite normal mode testing
    - Board + PC can get into a "BAD" state where the next boot will get characters from the PC at startup
    - With default U-boot any character received after the serial port is initialized with stop u-boot
    - Problem only occurs when the board sends "stuff" on the serial port when the PC does not have it open
        + "stuff" is unknown.  It is probably NOT the 00 character as both firmware versions send it
    - AND
    - then someone opens the port and closes it before the next boot
        + if the port remains open for the next boot, the problem does not happen

## WORKS: my boardctl script
* My scripts control the relays (using relayctl) and connect directly to the serial port via screen
* terminal 1

        $ ping 192.168.2.199
* terminal 2

        $ boardctl kv260 bootmode recovery; boardctl kv260 run
* terminal 3 (after board gets booted and terminal 1 is pinging)

        $ /usr/local/bin/kria-deploy.sh 192.168.2.199 .
* Note: board name in boardctl is kv260 not kv260-01
* Note: works with or without the ping terminal
* Note: boardctl always attaches a screen session to the tty

## WORKS: manual control
* manually control relays and run script w/o connecting to serial port at all
* terminal 1

        $ ping 192.168.2.199
* terminal 2

        $ SUDO ./test-recovery.sh
* SUDO above is to emulate dispatcher as much as possible
* The board responds to ping in 20 to 30 seconds
* Note: this works with or without the ping going on
* Note: This also works if I watch what is happening via telnet in another session like below
* Note: I ran this 10 times in a row with 30 second sleep in the script and it worked 10/10 times
    - It works with a 60 second sleep also of course

## DOES NOT WORK: running as a lava job
        $ lavacli --id local jobs submit --follow --polling 1 80-meta-ts-job.yml
* This starts the board in recovery mode and waits 60 seconds
* when the deploy script runs, the board does not respond to pings
* Note: this does not work with or without a terminal running ping
* Post Note: I figured out later that this actually works every other time

## WORKS again, watching the serial port as LAVA runs
* I reconfigured ser2net to enable kick-olduser
* This allows me to telenet in and watch what is happening as lava runs
* When lava needs the serial port (after the deploy sections) it gets it and kicks out my telnet session
* terminal 1

        $ ping 192.168.2.199
* terminal 2

        $ telnet localhost 7001
* terminal 3

        $ lavacli --id local jobs submit --follow --polling 1 80-meta-ts-job.yml

## Theory 1, something about serial port flow control
* I thought maybe the board was sending data to the port but it was then waiting for someone to read it before going on
    - This could be RTS/CTS or DTR/DSR
    - However the manual test above proves that this is not the case
    - Post Note: Later verified that board has no DTS/DSR/RTS/CTS connections for FDTI chip
* Maybe Lava was sending an XOFF?
    - Does u-boot or the kernel even honor this if it were to be RXed?
    - However we can tell Lava does not even connect to the board in the failure cases
    - We know this because we can telnet ourselves and we don't get kicked off until after the recovery

## Theory 2, U-boot is getting stopped by "hit any key"
* This seems to be the case, see below

## More testing (~2022-09-16)
* The meta-ts lava job actually works the first time after manual run
* The meta-ts lava job actually works after a FAILED meta-ts lava job
    - It works every other time
* The manual script fails after a "good" lava job has run
* Generally:
    - **recovery fails (LAVA or manual) after a LAVA job that connected to serial and has a deploy section **
* Connecting to telnet 30 seconds or so into a failing job finds a u-boot prompt
* Connecting to telnet after a "good" lava job seems to get a " " echoed to the screen
    - (later discovered that is really two byte sequence 00 20 (ie NUL SPACE)
    
## But strangely
* I can't get back to back lava jobs to fail if they don't contain deploy sections.
* I ran 10-just-boot-login.yml jobs several times back to back with no problem
    - I was using meta-ts firmware and the ledge sdcard image
* I tried a "good" meta-ts job (to get into a bad state) and then a just-boot-login and it was OK
* I used recovery-boot as the normal firmware and it still tried to boot
    - it did not stop at a prompt
    - (it did not boot all the way as it was not using BOOT0001, just the default)
    - (the ledge sdcard image does not support that, it starts the kernel and panics)

## Even more testing (~2022-09-16 overnight and 09-17)
* Verified it does not happen w/o deploy (overnight)
    - I deployed the recovery software (firmware and boot sdcard image) as a normal test payload

        $ ./lava/test2/test-recovery.sh
    - I created a "just boot" job that understands the recovery image 12-just-boot-login-root.yml
    - I ran that 100 times

        $ for i in {1..100}; do echo "****TEST $i *****"; lavacli --id local jobs submit --follow --polling 1 12-just-boot-login-root.yml; done
    - I looked at the LAVA server to verify all the jobs worked OK
* While testing with just boardctl and test-recovery.sh, I got occasional failures
* I re-created the issue w/o LAVA
    - With the board off, connect to telnet and type a few spaces
    - Run lava/test/test-recovery.sh, it will fail (Failed 3/3 tries)
* I recreated the issue w/o LAVA and w/o typing anything to telenet
    - Run lava/test/test-recovery.sh, ignore the result, this one is just to prime the problem
    - With the board now off connect and disconnect from telnet
        + you will notice telnet echos a "space" when you connect
    - Now run the lava/test/test-recovery.sh and it will fail
    - Repeat last two items 3 or more times, all fail
    - Note: if you leave the telenet session active, the script will work every time
* I recreated the issue w/o ser2net
    - As above but use screen to connect directly to the tty device
    - Note: if you leave the screen session active, the script will work every time
* I could NOT recreate the issue using minicom
    - minicom did echo the stray "space" character at startup
    - Tried ^AX (exit with reset) and ^AQ (exit w/o reset) both showed no problem
    - Tried with HW flow control enabled and disabled, both showed no problem
    - Of course leaving the session active also shows no problem
* Configure ser2net to ignore CTS
    - local only ignores DSR (and I assume CD)
    - "-RTSCTS" option disables HW flow control, RTSCTS enables it
    - doing this makes does not make a difference
        + I initially thought it did but it did not work in LAVA and when I retested I found no change
        + I may have been testing with meta-ts as the firmware which I now know does not show the problem
        + I am happy with this as I could not see how this could have fixed anything
    - DOES NOT fix things for LAVA
    - This should not have changed anything and it did not
      + stty while telnet is connected shows hw flow control off with or without this new option
      + If RTSCTS flow control was actually on then it should never transmit to the card as CTS line is NC
* Use minicom -H mode to see "stuck" character
    - shows as two bytes: 00 20
* Use gtkterm to watch modem signals
    - has good control
        + has hex view mode
        + has raw file save
        + has toggle DTR and toggle RTS
        + has open port and close port commands
        + displays DSR CTS CD RI (as well as current DTR and RTS)
    - shows stuck character as 00 20, same as minicom
    - save of raw log shows only 1 00 character,  It is the first character from FSBL
        + 00 20 does not appear in log
    - toggling DTR and RTS off does not seem to change anything
        + they get enabled on next "open port"

## More testing after fixing recovery-boot.bin
* I used the previously broken recovery-boot.bin as ImageA.bin
    - used the recovery-boot-sdcard.img for sd
    - was able to reproduce the issues with telnet and the script
        + this was WITH -RTSCTS option in ser2net.yaml
        + I don't think this ever fixed things.  I must have been doing something wrong
* I used the meta-ts test image firmware 
    - setup 
        + used as ImageA.bin and ImageB.bin
        + These are a matched set and must be used together.
        + I used the same sd card image
        + With this setup etherenet does not work in kernel so ping test will always fail
        + I used the heat-beat led to visually verify if the kernel started or not.
    - results
        + could not reproduce the issue, kernel always boots
        + No "space" seen on telnet
* Comparing versions
    - Old recovery-boot.bin
        + Uses FSBL
        + Uses Xilinx U-boot based on 2022.01 w/ lot of Xilinx patches
        + shows the issue
    - meta-ts firmware
        + Uses SPL
        + Uses upstream U-boot (2022.07 or .10 for this image)
        + does not show the issue
    - Both
        + print 00 character as first output
        + are configure to stop "on any key"
        + are NOT configured to flush stdin before counting

## Calling it quits
* I have spent 3 solid days on this
* The problem is well characterized
* The firmware we use the most does not show the problem
* A modern setting for autoboot stop avoids the problem if seen again
* The actual root cause is still not understood

## Actions
* Rebuild recovery-boot with a unique autoboot stop key (DONE)
    - This should fix the recovery problem (IT DOES)
    - Recovery should be robust so we should be doing this anyway
* Check boards FTDI DTS/DTR/RTS/CTS connections (DONE)
    - The only connections for the FTDI chip for -if01 (main console) is TX & RX
    - all other pins for this port are not connected
    - This is true of -if02 (2nd UART)
    - There is no 3rd UART, -if03 if misc board control
    - (-if0 is JTAG but I knew that already)
* Figure out root cause
    - where do these extra characters comes from
    - where do they get stuck?
        + buffered in ser2net? or tty driver? FTDI chip?
        + does not seem to be ser2net as I can reproduce with screen
    - why are they stuck
        + serial port input buffer and stuck because no one has opened port?
        + why don't we see this with other input when the port is not open?
    - how do they get echoed back to board to cause u-boot autoboot to stop?
        + It can't be HW flow control as there is none
    - why is it echoed on connect to telnet even if board is powered off
        + stuck in the driver or ftdi?
    - ser2net ,local option should ignore HW signals right?
        + Is this just DSR?  Is there another option for CTS?
* Figure out why lava job w/o deploy is OK? (DONE)
    - meta-ts is still looking for "any key"
        + maybe it flushes existing input before the prompt? (It does not)
    - even using recovery-boot still works in this case
        + problem only happens when "stuff" is sent by the board when the port is not open
        + it also then requires someone to open the port
