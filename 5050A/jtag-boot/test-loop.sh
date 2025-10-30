#!/bin/bash

NOW=$(date +%Y-%m-%d-%H-%M-%S)

NUM=20
if [ -n "$1" ]; then
    NUM=$1
fi

rm -f results-$NOW.txt
touch results-$NOW.txt
ln -sf results-$NOW.txt results.txt

for i in $(seq 1 $NUM); do
    echo "test # $i" | tee -a results.txt
    ./test.sh;
done
