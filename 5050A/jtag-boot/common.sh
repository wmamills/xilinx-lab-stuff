# to be sourced not run

X86_IP=192.168.157.48
ARM_IP=192.168.157.49

test_ping() {
    IP=$1; shift
    if ping -c 1 $IP >/dev/null 2>&1 ; then
        echo "ping OK     for $IP $@"
    else
        echo "ping FAILED for $IP $@"
    fi
}

test_ssh() {
    IP=$1; shift
    if ssh -o ConnectTimeout=5 $IP true >/dev/null 2>&1 ; then
        echo "ssh  OK     for $IP $@"
    else
        echo "ssh  FAILED for $IP $@"
    fi
}

wait_ping() {
    echo "waiting for $1 to ping"
    while ! ping -c 1 $1 >/dev/null 2>&1 ; do
        echo -n "."
        sleep 1
    done
    echo " OK"
}

wait_ssh() {
    echo "waiting for ssh on $1 to be active"
    while ! ssh -o ConnectTimeout=5 $1 true >/dev/null 2>&1 ; do
        echo -n "."
        sleep 1
    done
    echo " OK"
}


