# NetPol Builder

The NetPol Builder chart converts a high-level firewall-style `values.yaml` into deterministic Kubernetes NetworkPolicies. The goal is to eliminate hand-written policies, enforce consistency, and keep developers from editing raw NetworkPolicy YAML.

---

## Concept

You write intent in a single `values.yaml`:
  NetPol Builder converts that into:

  - Egress NetworkPolicies
  - Ingress NetworkPolicies
  - Namespace-wide default deny policies
  - Optional DNS and monitoring exceptions

You only maintain `values.yaml`; the chart generates the NetworkPolicy objects.

---

## `values.yaml` structure

Below is a clean, consistent example you can use as a starting point.

```yaml
# Namespace this file applies to
namespace: frontend

# Feature toggles interpreted by the generator/operator
features:
  ingress: true        # Allow external ingress / Route exposure
  monitoring: false    # Enable metrics scrapes / netobserv integration

# Selector mapping (optional)
# Maps friendly names → Kubernetes label selectors for workloads
# If omitted for a workload, "app: <name>" is assumed.
selectors:
  checkout:
    matchLabels:
      demo: label

# Firewall-style traffic rules
rules:

  - id: checkout-to-gateway-8080
    src:
      workload: checkout
    dst:
      workload: gateway
      service: 8080/tcp

  - id: checkout-to-payments-gateway-8080
    src:
      workload: checkout
    dst:
      namespace: payments
      workload: gateway
      service: 8080/tcp

  - id: webapp-to-checkout-8080
    src:
      namespace: frontend
      workload: webapp
    dst:
      workload: checkout
      service: 8080/tcp

  - id: reports-to-subnet
    src:
      workload: reports
    dst:
      cidr: 10.20.30.0/24
      service: any

  - id: any-to-subnet
    src:
      any: true
    dst:
      cidr: 10.20.30.0/24
      service: any

  - id: any-to-payments-gateway-8443
    src:
      any: true
    dst:
      namespace: payments
      workload: gateway
      service: 8443/tcp

  - id: egress-to-www-google.com
    dst:
      fqdn: www.google.com
      service: 443/tcp

  - id: egress-to-db-google.com
    dst:
      fqdn: db.google.com
      service: 443/tcp
```

### Semantics

- `namespace`: The namespace where all generated NetworkPolicies will be applied.
- `features.ingress`:
  - `true`: add policies to allow traffic from OpenShift ingress / Routes.
  - `false`: do not add ingress router exceptions.
- `features.monitoring`:
  - `true`: allow scraping from monitoring namespaces.
  - `false`: do not add monitoring-specific allows.
- `selectors` (optional): If you define `selectors.<name>`, that mapping is used to select pods. If omitted, the generator assumes:

```yaml
matchLabels:
  app: <workload-name>
```

- `rules`:
  - `src`:
    - `workload: <name>` → pods matching that workload in the current namespace
    - `namespace: <ns>, workload: <name>` → pods in another namespace
    - `any: true` → all pods in this namespace
    - If `src` is omitted: treat as "all pods in this namespace"
  - `dst`:
    - `workload: <name>` → target workload in this namespace
    - `namespace: <ns>, workload: <name>` → workload in another namespace
    - `cidr: <CIDR>` → external subnet (e.g. `10.20.30.0/24`)
    - `fqdn: <host>` → external FQDN (e.g. `www.google.com`)
    - `service: <port>/<proto>` or `any` → port and protocol

---

## What the chart generates

From `values.yaml`, NetPol Builder generates:

- A namespace-wide default deny for ingress and egress
- Ingress and Egress policies for each rule
- Extra rules for:
  - `features.ingress`: OpenShift router → workloads
  - `features.monitoring`: monitoring namespaces → workloads
  - FQDNs: DNS egress policies where required

You only maintain `values.yaml`; the chart maintains the NetworkPolicies.

---

## Helm OCI workflow (Quay)

Registry-based usage examples.

### Install (first deployment)

Deploy the chart directly from Quay with your custom values:

```sh
helm install netpol-builder \
  oci://quay.io/ralvares/netpol-builder \
  --version 0.1.0 \
  -n frontend \
  -f values.yaml
```

Outcome: The chart is pulled from the OCI registry, rendered with `values.yaml`, and NetworkPolicies are applied in the `frontend` namespace.

### Upgrade (new values)

When you change `values.yaml` (new rules, removed rules, toggles):

```sh
helm upgrade netpol-builder \
  oci://quay.io/ralvares/netpol-builder \
  --version 0.1.0 \
  -n frontend \
  -f values.yaml
```

Outcome: Helm re-renders the policies and applies only the changes.

### Rollback (restore a known-good revision)

List previous revisions:

```sh
helm history netpol-builder -n frontend
```

Rollback:

```sh
helm rollback netpol-builder <REVISION> -n frontend
```

Outcome: The cluster returns to the exact policy set from that revision. If a change blocks critical traffic, you can revert without touching any NetworkPolicy YAML.

---

## How to work with it day-to-day

- Developers:
  - Propose changes in `values.yaml` (new connections, removed connections)
- Platform / Security:
  - Review the `values.yaml` diff (rather than NetworkPolicy YAML)
- CI / CD:
  - Run `helm upgrade` (or Argo CD / GitOps sync) to apply new policies
- Operations:
  - Use `helm history` / `helm rollback` as the safety net

You get a consistent, auditable, and reversible way to manage Kubernetes NetworkPolicies, with a simple `values.yaml` as the source of truth.

