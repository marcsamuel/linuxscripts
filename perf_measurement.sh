#!/bin/bash
#
# Expects to be run as root
# Records various stats for 60 seconds at a time
# Creates a tar.gz artifact with all data in it

#
# Check to whether or not the current user is root; if not it exits
#
set -u

printf "Root Check\n"
if [ $(id -u) != 0 -o $(id -g) != 0 ]; then
        echo "Must be root to run this script! Exiting diagnostics."
    exit 1
fi

#
# Attempt to gather the CID and AID
#
cid=`/opt/CrowdStrike/falconctl -g --cid | grep -o -P '([a-zA-Z0-9]*)' | tail -n 1`
if [ -z $cid ]; then
    cid="unset"
fi
aid=`/opt/CrowdStrike/falconctl -g --aid | grep -o -P '([a-zA-Z0-9]*)' | tail -n 1`
if [ -z $aid ] || [ $aid == "set" ]; then
    aid="unset"
fi

function finish {
    #
    # Xz up the artifacts
    #
    echo "Creating tar.xz of the results"
    tar -cvJf perf-$cid-$aid-$(date +%F-%H-%M).tar.xz $perf_dir/
}

trap finish EXIT

#
# Identify host operating system, and use the appropriate method to
# install perf on the host. If perf is not already installed it will
# ask the user if they want to install it. If they indicate no, it
# will exit out. If the distro is unable to be recognized, it will
# exit out with a message denoting such
#
# Ray: At this point it does not ask the user. It just installs perf. We may
#      want to change it to just checking if perf is installed.
#
redhat-version () {
    printf "$(cat /etc/redhat-release | cut -d' ' -f3 | cut -f1 -d'.')"
}

auto-install-yum () {
    YUM_VERBOSITY=
    if rpm -q $1; then
        echo "Already installed $1: $(rpm -q $1)"
    else
        echo "Installing $1 ..."
        if which dnf; then
            dnf ${YUM_VERBOSITY} -y install $1
        else
            yum ${YUM_VERBOSITY} -y install $1
        fi
    fi
}

auto-install-zypper () {
    if rpm -q $1; then
        echo "Already installed $1: $(rpm -q $1)"
    else
        echo "Installing $1 ..."
        zypper --non-interactive install $1
    fi
}

auto-install-deb () {
    name=$(echo $1 | sed -e 's/-devel/-dev/')
    if dpkg -s $name; then
        echo "Already installed $name: $(dpkg -s $name)"
    else
        echo "Installing $name ..."
        apt-get -y install --no-install-recommends $name
    fi
}

auto-install () {
    if [ -e /etc/redhat-release ]; then
        auto-install-yum $@
    elif [ -e /etc/debian_version ]; then
        auto-install-deb $@
    elif [ -e /etc/SuSE-release ]; then
        auto-install-zypper $@
    elif [ -e /etc/system-release ]; then
        auto-install-yum $@
    else
        echo "Unknown distribution, quitting."
        exit 1
    fi
}


auto-install perf

#
# Set time argument. This denotes how long of a period it gathers perf
# data for. By default, this is set to 60 seconds per command for a total
# run-time of approx. 5 minutes.
#
if [ "$#" -ne 1 ]
then
    run_time=60
else
    run_time=$1
fi

echo "Running perf"

#
# This script creates a working directory. Before running, it checks to see
# if the directory already exists, and deletes it, to get rid of any data
# from previous runs to prevent confusion.
#
perf_dir="perf_measurement"
if [ -d $perf_dir ]; then
    rm -rf $perf_dir
fi

mkdir $perf_dir

#
# Grab falcon-sensor rpm information
#
if [ "$(command -v rpm)" ]; then
    rpm -qi falcon-sensor > $perf_dir/rpm_falcon.txt
fi

#
# Grab perf list
#
perf list > $perf_dir/perf_list.txt

#
# ls* utilities
#
if [ -x "$(command -v lsblk)" ]; then
    lsblk > $perf_dir/lsblk.txt
fi
if [ -x "$(command -v lscpu)" ]; then
    lscpu > $perf_dir/lscpu.txt
fi
if [ -x "$(command -v lsipc)" ]; then
    lsipc > $perf_dir/lsipc.txt
fi
if [ -x "$(command -v lslocks)" ]; then
    lslocks > $perf_dir/lslocks.txt
fi
if [ -x "$(command -v lsmod)" ]; then
    lsmod > $perf_dir/lsmod.txt
fi
if [ -x "$(command -v lsns)" ]; then
    lsns > $perf_dir/lsns.txt
fi
if [ -x "$(command -v lsof)" ]; then
    lsof > $perf_dir/lsof.txt
fi

#
# Collect falcon-sensor information
#
if [ -d "/opt/CrowdStrike" ]; then
    ls -al /opt/CrowdStrike > $perf_dir/ls_falcon.txt
    dir /opt/CrowdStrike > $perf_dir/dir_falcon.txt
fi

timer="-- sleep $run_time"

echo "Collecting stats"

#
# This step shows everything that you can look at with perf, including
# scheduler, block, kmem, faults, etc. This info is saved in perf_stats.txt
#
perf_list=`perf list`
events=""
if [[ $perf_list == *"sched"* ]]; then
    events+="sched:*,"
fi
if [[ $perf_list == *"block"* ]]; then
    events+="block:*,"
fi
if [[ $perf_list == *"kmem"* ]]; then
    events+="kmem:*,"
fi
if [[ $perf_list == *"major-faults"* ]]; then
    events+="major-faults,"
fi
if [[ $perf_list == *"minor-faults"* ]]; then
    events+="minor-faults,"
fi
if [[ $perf_list == *"context-switches"* ]]; then
    events+="context-switches,"
fi
if [[ $perf_list == *"filelock"* ]]; then
    events+="filelock:*,"
fi
if [[ $perf_list == *"filemap:"* ]]; then
    events+="filemap:*,"
fi
if [[ $perf_list == *"exceptions"* ]]; then
    events+="exceptions:*,"
fi
if [[ $perf_list == *"module"* ]]; then
    events+="module:*,"
fi
if [[ $perf_list == *"net"* ]]; then
    events+="net:*,"
fi
if [[ $perf_list == *"power"* ]]; then
    events+="power:*,"
fi
if [[ $perf_list == *"printk"* ]]; then
    events+="printk:*,"
fi
if [[ $perf_list == *"rcu"* ]]; then
    events+="rcu:*,"
fi
if [[ $perf_list == *"syscalls"* ]]; then
    events+="syscalls:*,"
fi
events=${events: : ${#events}-1}

perf stat -e $events -a -o $perf_dir/perf_stats.txt $timer

#
# Looks at all processes run during the test period. This is info that the
# sensor is capable of seeing, but it is not impacted by bounding limits
# the way the sensor is. This info is saved to perf_sched_report.txt.
#
if [[ $perf_list == *"sched_process_exec"* ]]; then
    echo "Collecting exec information"
    perf record -e sched:sched_process_exec -a -o $perf_dir/perf_sched.data $timer
    perf report -nf --stdio -i $perf_dir/perf_sched.data > $perf_dir/perf_sched_report.txt
fi

#
# This generates call graphs, which are used to report a stack trace. The
# argument -a checks all CPUs, -g is a stack trace, -F 999 means 999 Hertz
# (we collect info 999 times a second). This writes to
# perf_whole_system_report.txt
#
echo "Collecting whole system callgraph information"
options="-a -F 999 -g"
if [[ `perf --help` == *"proc-map-timeout"* ]]; then
    options+=" --proc-map-timeout=5000"
fi
perf record $options -o $perf_dir/whole_system.data $timer
perf report -nf --stdio -i $perf_dir/whole_system.data > $perf_dir/perf_whole_system_report.txt

#
# This collects the same info as above, but looking at the Falcon sensor rather
# than the whole system. If the Falcon sensor isn't running, it will echo
# stating such.
#
echo "Collecting falcon-sensor callgraph information"
pid=`pgrep falcon-sensor`
if [ ! -z $pid ]; then
    options="-F 999 -p $pid -g"
    if [[ `perf --help` == *"proc-map-timeout"* ]]; then
        options+=" --proc-map-timeout=5000"
    fi
    perf record $options -o $perf_dir/falcon_sensor.data $timer
    perf report -nf -g folded --stdio -i $perf_dir/falcon_sensor.data > $perf_dir/perf_falcon_report.txt
else
    echo "falcon-sensor NOT running!" | tee $perf_dir/perf_falcon_report.txt
fi

#
# Lists and copies needed libraries for remote analysis
#
for item in `perf buildid-list -f --input=$perf_dir/falcon_sensor.data`; do
    # fake up dir and copy library
    if [ -f "$item" ]; then
        full_path=$item
        directory=`dirname $full_path`
        file_name=`basename $full_path`

        mkdir -p .$perf_dir/$directory
        cp $full_path .$perf_dir/$full_path
    fi
done

#
# Lists and copies all the symbols in the kernel for remote analysis
#
mkdir $perf_dir/proc
cp /proc/kallsyms $perf_dir/proc/kallsyms

echo "Perf completed"
