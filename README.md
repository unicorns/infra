# Infrastructure Configuration

```bash
git fetch \
&& docker compose build provisioner \
&& docker compose run --rm provisioner /bin/bash
```

### TODOs

- [ ] Back up Terraform state
- [ ] Back up Vault data
