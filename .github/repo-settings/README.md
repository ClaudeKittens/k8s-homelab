# repo-settings

OpenTofu/Terraform code that manages the GitHub repository settings for this repo.

## Usage

Requires a GitHub token with `repo` and `admin:org` scopes in `GITHUB_TOKEN`.

```sh
tofu init
tofu plan
tofu apply
```

Import the existing repo on first run:

```sh
tofu import github_repository.k8s_homelab k8s-homelab
```
