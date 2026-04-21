# gnmic → OTLP → OTel Collector → Prom remote_write lab

Quick-and-dirty containerlab demonstrating a simnple network telemetry pipeline. Two independent flows converge at the OTel Collector and land in Grafana.

### Metrics (gNMI → Prom)

![Metrics flow: gNMI sources through gnmic and the OTel Collector to Prometheus and Grafana](docs/images/metrics-flow.svg)

### Logs (syslog → Loki)

![Logs flow: router syslog through the OTel Collector to Loki and Grafana](docs/images/logs-flow.svg)

## Prereqs

- Docker + [containerlab installed](https://containerlab.dev/install/)
- cEOS-lab image [imported](https://containerlab.dev/manual/kinds/ceos/) into Docker. Confirm with:
  ```
  docker images | grep ceos
  ```
  Adjust the `image:` tag in `topo.clab.yml` if yours is tagged differently (e.g. `ceos:4.32.0F` vs `ceos:latest`).

## Bring it up

```bash
cd gnmic-otel-lab
containerlab deploy -t topo.clab.yml
  ```

## Create traffic

Interface counters only move if something's crossing the data plane. `./traffic.sh` wraps iperf3 on `host2` → `host1` (8 parallel TCP streams, ≈1.6 Mbit/s total) so the rate panels in Grafana have something to show:

To start traffic
```bash
./traffic.sh start
```
To stop the traffic
```
./traffic.sh stop
```

## Web UIs

- **Prometheus** http://localhost:9090
- **Grafana** http://localhost:3000 (anonymous Admin enabled, or admin/admin). A pre-provisioned dashboard **"gNMI → OTLP → Prom Lab"** (uid `gnmic-otel-lab`) shows data-plane rates, collector throughput, and remote-write health. Loki is wired in as a datasource; explore logs via Grafana's Explore tab.

## Teardown

```bash
containerlab destroy -t topo.clab.yml --cleanup
```

## Quick tshooting steps if things aren't working

Quick per-component health checks, roughly in the order data flows. Each one tells you whether that hop is alive and passing something downstream if a later check fails, the first failing hop is where to look.

Of the seven internal components, only four expose ports to the host: **otelcol** (4317, 4318, 13133, 1777, 5514/udp), **prometheus** (9090), **loki** (3100), **grafana** (3000). gnmic and the routers are only reachable via `docker exec` or over the `clab-mgmt` bridge. gnmic's self-metrics and the collector's self-telemetry both flow through the pipeline into Prom, so **Prometheus is the canonical place to check internal-component health** not each container's own /metrics endpoint.

### Switches: cEOS and SR Linux (gNMI targets)

gNMI reachable and authenticating (`/app/gnmic` is the binary path inside the gnmic container):
```bash
docker exec clab-gnmic-otel-lab-gnmic \
  /app/gnmic -a 172.22.22.11:6030 -u admin -p admin --insecure capabilities | head
docker exec clab-gnmic-otel-lab-gnmic \
  /app/gnmic -a 172.22.22.12:57400 -u admin -p 'NokiaSrl1!' --skip-verify capabilities | head
```
Expect `gNMI version` + supported models. `Unauthenticated` on cEOS usually means missing gNMI user or `management api gnmi` not enabled.

eBGP session up between them:
```bash
docker exec clab-gnmic-otel-lab-ceos1 Cli -p 15 -c "show ip bgp summary"
docker exec clab-gnmic-otel-lab-srl1  sr_cli "show network-instance default protocols bgp neighbor"
```
Expect state `Estab` / `established` with PfxRcd ≥ 1.

### gnmic

Subscriptions established, no errors:
```bash
docker logs --tail 50 clab-gnmic-otel-lab-gnmic | grep -iE "subscribing|error|validation"
```
Expect `subscribing to target` lines and no `VALIDATION ERROR` / `connection refused`.

Target health, via Prom (otelcol scrapes gnmic:7890 and forwards):
```bash
curl -s 'localhost:9090/api/v1/query?query=gnmic_target_up' | head -c 400; echo
```
Expect `"value":[...,"1"]` per target. `0` or no result = target unreachable from gnmic.

OTLP output counters; should be nonzero and growing:
```bash
curl -s 'localhost:9090/api/v1/query?query=gnmic_otlp_output_number_of_sent_events_total' | head -c 400; echo
curl -s 'localhost:9090/api/v1/query?query=gnmic_otlp_output_number_of_failed_events_total' | head -c 400; echo
```
Sent climbing + failed flat = healthy.

### OpenTelemetry Collector

Liveness:
```bash
curl -s localhost:13133/
```

Flow-through, via Prom (collector pushes its own telemetry via OTLP loopback):
```bash
curl -s 'localhost:9090/api/v1/query?query=otelcol_receiver_accepted_metric_points_total' | head -c 400; echo
curl -s 'localhost:9090/api/v1/query?query=otelcol_exporter_sent_metric_points_total'     | head -c 400; echo
```
Both should be increasing. If accepted grows but sent doesn't, the exporter is wedged.

### Loki

Ready + labels populated (proves logs are landing):
```bash
curl -s localhost:3100/ready
curl -s localhost:3100/loki/api/v1/labels | head -c 300; echo
```
(A brief `Ingester not ready: waiting for 15s after being ready` right after bring-up is normal.)

Bytes received, via Prom:
```bash
curl -s 'localhost:9090/api/v1/query?query=loki_distributor_bytes_received_total' | head -c 400; echo
```

### Prometheus

End-to-end, sample gnmic metric through the full chain:
```bash
curl -s 'localhost:9090/api/v1/query?query=gnmic_port_stats_interfaces_interface_state_counters_in_octets' \
  | head -c 500; echo
```
Empty result = chain broken upstream. A constant value = chain works but no traffic (see Hosts).

### Grafana

API up and datasources provisioned:
```bash
curl -s localhost:3000/api/health
curl -s -u admin:admin localhost:3000/api/datasources | head -c 400; echo
```
UI at http://localhost:3000 (anonymous Admin enabled).

## Notes

1. **gnmic counter-patterns default is empty** every metric becomes
   a Gauge unless you configure regex patterns. This config flags
   `octets|packets|bytes|errors|discards|drops` as Sums. Without this,
   `rate()` queries silently give wrong answers.

2. **gnmic resource-tag-keys default is empty** all tags become
   data-point attributes (Prom labels). We lift `source` and `target`
   to OTLP Resource attributes for saner downstream filtering.

3. **Collector memory_limiter goes first in the pipeline**, always.
   At the limit it *refuses* data, upstream retries, not graceful
   degradation. Still better than OOMing.

4. **Prom remote_write receiver requires `--web enable-remote-write-receiver`**.
   Missing that flag = silent 404s from the collector side.

5. **`resource_to_telemetry_conversion: enabled`** on the remote_write
   exporter promotes every Resource attribute to a Prom label on every
   series.

6. **cEOS appears to freeze the gNMI Notification timestamp on unchanged leaves** 
   (e.g. `components/component/state/memory/available`). It keeps
   re-sending the value at every sample interval, but stamped with the
   original sample time, forever. gnmic's OTLP output uses the notification
   timestamp verbatim, so Prometheus sees the same ancient datapoint and
   drops the series past its default 5-minute `lookback-delta`. The metric
   silently vanishes from instant queries ~5 min after bring-up even though
   samples are still arriving on the wire. Fix in this lab: an
   `event-override-ts` processor on the gnmic OTLP output rewrites each
   event timestamp to `now()`. Trades true sample-time fidelity for
   continuity.

## Things to try from here

- Add a `transform` processor to the collector
- Turn on `debug` exporter with `verbosity: detailed` to see raw
  OTLP structure flowing through the collector.

