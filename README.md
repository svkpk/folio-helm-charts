# Folio kubernetes installation

Copyright 2023 SVKPK

Licensed under the Apache License, Version 2.0. See the file "[LICENSE](LICENSE)" for more information.

## Dependencies

Needs to be created out of this setup

* ElasticSearch
* PostgreSQL
* Minio
* Kafka
* Kubernetes cluster
* Helm

## Docker images & charts

### Docker images

#### Okapi

Okapi + tools to run & setup okapi (hazelnut cluster included).

#### Foliotools

Folio tools.

#### Okapiclient

Okapi client tools.

#### Tenant

Frontend for specific tenant including tenant setup.

### Charts

#### Okapi

Okapi instance (hazelnut cluster included).

#### Module

Folio module/modules install chart.

#### Tenant

## Usage / Install process

0. Prepare global settings
1. Install Okapi
2. Install Auth modules
3. Secure supertenant
4. Install the rest of modules
5. Setup tenant and install frontend containers

### Prepare global settings and chart repo

* Copy and update `charts/values-global.yaml`
* Add helm charts repository
* Export target kubernetes namespace

```bash
helm repo add svkpk-folio https://folio.pages.svkpk.cz/folio-helm-charts
```

### Install Okapi

Run helm upgrade/install command:

```bash
helm upgrade --install --wait --atomic --timeout 30m \
  --values values-global.yaml \
  --namespace="$KUBE_NAMESPACE" \
  okapi svkpk-folio/okapi
```

### Install Auth modules

```bash
helm upgrade --install --wait --atomic --timeout 30m \
  --values values-global.yaml \
  --values values-modules-no-auth.yaml \
  --namespace="$KUBE_NAMESPACE" \
  modules-auth svkpk-folio/module
```

### Secure supertenant

```bash
helm upgrade --install --wait --atomic --timeout 30m \
  --values values-global.yaml \
  --values values-supertenant.yaml \
  --namespace="$KUBE_NAMESPACE" \
  supertenant svkpk-folio/supertenant
```

### Install the rest of modules

```bash
helm upgrade --install --wait --atomic --timeout 30m \
  --values values-global.yaml \
  --values values-modules-rest.yaml \
  --namespace="$KUBE_NAMESPACE" \
  modules-rest svkpk-folio/modules
```

### Setup tenant and install frontend container

```bash
helm upgrade --install --wait --atomic --timeout 30m \
  --values values-global.yaml \
  --values values-tenant.yaml \
  --namespace="$KUBE_NAMESPACE" \
  tenant-skvpk svkpk-folio/okapi
```
