#!/bin/bash
# Launched via: docker exec host2 bash /config/iperf.sh
#
# 8 parallel TCP streams @ 200 Kbit/s each == 1.6 Mbit/s total.
# Long duration so it stays up across the lab session; traffic.sh stops it.
iperf3 -c 10.0.1.2 -t 10000 -i 1 -p 5201 -B 10.0.2.2 -P 8 -b 200K -M 1460 &
