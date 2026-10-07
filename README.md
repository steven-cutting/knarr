# Knarr

A Kubernetes controller, written in Gleam on the BEAM, that biases Deployment scale-down away from busy worker pods. It polls each worker over HTTP and sets `controller.kubernetes.io/pod-deletion-cost` (and optionally `cluster-autoscaler.kubernetes.io/safe-to-evict`) on the pod.

See [docs/OVERVIEW.md](docs/OVERVIEW.md) for the project overview, goals, worker contract draft and open questions.
