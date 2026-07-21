# network-boundary

Captures the segmentation contract for GridGuard environments.

This module currently emits metadata and invariants only. That is deliberate:
the local environment is Docker Compose, and the cloud environment has not been
chosen deeply enough to create real network resources. When AWS resources are
added, preserve this module interface and map it to VPC subnets, route tables,
security groups, and network ACLs.
