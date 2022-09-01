#!/bin/bash

mkimage -f recovery-fit.its recovery.fit
mkimage -T script -d recovery-script.txt recovery-script.scr

