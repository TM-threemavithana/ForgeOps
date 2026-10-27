# G09 — Observability Acceptance Evidence

## Outcome

**Status: PASSED**

ForgeOps G09 provides GitOps-managed observability through
Prometheus, Grafana, Alertmanager, and Prometheus Operator
on the `kind-forgeops` Kubernetes cluster.

## Runtime acceptance

| Verification | Result |
|---|---|
| Prometheus Operator | Ready |
| Prometheus | Ready |
| Alertmanager | Ready |
| Grafana | Ready |
| Prometheus PVC | Bound, 2 GiB |
| Prometheus scrape targets | 7/7 UP |
| ForgeTasks rehearsal metrics | `/actuator/prometheus` UP |
| Grafana Prometheus datasource | Health OK |
| G09 Argo CD | Synced / Healthy |
| G08 Argo CD | Synced / Healthy |

## Controlled alert lifecycle

Alert: `G09AlertPipelineDrill`

| Stage | Observed result | UTC timestamp |
|---|---|---|
| Pending | Prometheus rule entered Pending | 2026-10-27T07:21:41.893796+00:00 |
| Firing | Prometheus rule entered Firing | 2026-10-27T07:22:55.981020+00:00 |
| Delivery | Alertmanager received active alert | 2026-10-27T07:22:55.986589+00:00 |
| Resolution | Prometheus and Alertmanager cleared | Confirmed by restoration evidence |

### Activation

- Expression: `vector(1) == 1`
- Hold duration: `1m`
- Git activation revision: `65491e8d3b66ea7180ce226067a2219fc9612e6e`
- Prometheus Pending and Firing states confirmed
- Alertmanager receipt confirmed

### Restoration

- Original expression restored: `vector(0) == 1`
- Hold duration remains `1m`
- Git restoration revision: `37697bf64949088d288aa718c5bc6b3e69c934b3`
- Prometheus rule returned to `inactive / ok`
- No remaining active drill alert in Prometheus or Alertmanager

## Safety controls

- Deployment through reviewed GitHub pull requests
- Argo CD manual synchronization
- Pruning disabled during controlled synchronization
- Receiver-safety preflight found no outbound notification integrations
- G08 remained Synced / Healthy
- No G06 or G08 application/database modifications were requested

## Evidence files

- [Alert activation](alert-activation.json)
- [Alert restoration](alert-restoration.json)

## Related pull requests

- [#26 — Monitoring startup correction](https://github.com/TM-threemavithana/ForgeOps/pull/26)
- [#27 — Alert drill activation](https://github.com/TM-threemavithana/ForgeOps/pull/27)
- [#28 — Alert drill restoration](https://github.com/TM-threemavithana/ForgeOps/pull/28)

## Final state

The G09 monitoring stack was verified `Synced / Healthy`.
The controlled drill was restored to its original inactive
expression and the alert was cleared from both monitoring APIs.
