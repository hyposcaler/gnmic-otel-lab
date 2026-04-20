#!/bin/bash
# Start / stop iperf3 traffic between host2 (initiator) and host1 (server).
# Mirrors the srl-telemetry-lab pattern: orchestrator on host OS,
# worker script bind-mounted into the container at /config/iperf.sh.
#
# usage:
#   ./traffic.sh start
#   ./traffic.sh stop

set -eu

start() {
    echo "starting iperf3 traffic: host2 -> host1 (via ceos1 -> srl1)"
    docker exec clab-gnmic-otel-lab-host2 bash /config/iperf.sh
}

stop() {
    echo "stopping iperf3 on host2"
    docker exec clab-gnmic-otel-lab-host2 pkill iperf3 || true
}

case "${1:-}" in
    start) start ;;
    stop)  stop ;;
    *) echo "usage: $0 {start|stop}"; exit 1 ;;
esac
