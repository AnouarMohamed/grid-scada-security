# local-dev Terraform Environment

`local-dev` describes the Docker Compose integration environment as Terraform
metadata. It does not create the containers; Compose does that. The purpose of
this environment is to lock in the architecture contract that cloud resources
must later satisfy.

Use it to answer:

- Which zones exist?
- Which services may cross the OT/cloud boundary?
- Which endpoints are allowed to be exposed to the host?
- Which invariants should stay true when this becomes cloud infrastructure?

Validate from the repository root:

```bash
make terraform
```
