# Mermaid diagram sources

Source files for the diagrams embedded in the top-level `README.md`.

| Source | Rendered output |
| ------ | --------------- |
| `flow.mmd` | `../images/flow.svg` |
| `topology.mmd` | `../images/topology.svg` |

## Rendering

The [`minlag/mermaid-cli`](https://hub.docker.com/r/minlag/mermaid-cli) image ships `mmdc` with Puppeteer pre-configured, so you don't need Node or headless Chrome on the host.

From the repo root:

```bash
# flow diagram (gNMI / SNMP / syslog pipeline)
docker run --rm -u $(id -u):$(id -g) -v "$PWD":/data \
  minlag/mermaid-cli -i /data/docs/mermaid/flow.mmd -o /data/docs/images/flow.svg

# network topology (host1 / ceos1 / srl1 / host2)
docker run --rm -u $(id -u):$(id -g) -v "$PWD":/data \
  minlag/mermaid-cli -i /data/docs/mermaid/topology.mmd -o /data/docs/images/topology.svg
```

`-u $(id -u):$(id -g)` keeps the output file owned by you instead of root.

## Notes on `flow.mmd`

- Uses YAML frontmatter (`---\nconfig:\n  flowchart:\n    defaultRenderer: elk\n---`) to select the ELK renderer. Mermaid's default (dagre) doesn't minimize edge crossings; the `srl` gNMI + syslog edges overlap under dagre but route cleanly under ELK.
- The old `%%{init: ...}%%` directive form didn't parse cleanly with mermaid-cli 11.x here; the YAML frontmatter is the supported replacement.
