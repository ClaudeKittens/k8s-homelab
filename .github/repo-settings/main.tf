resource "github_repository" "k8s_homelab" {
  name        = "k8s-homelab"
  description = "Experiments in running Kubernetes on home compute — one folder per approach"
  visibility  = "public"

  has_issues   = true
  has_projects = false
  has_wiki     = false

  allow_merge_commit     = false
  allow_squash_merge     = true
  allow_rebase_merge     = true
  delete_branch_on_merge = true

  squash_merge_commit_title   = "PR_TITLE"
  squash_merge_commit_message = "PR_BODY"
}

resource "github_branch_protection" "main" {
  repository_id = github_repository.k8s_homelab.node_id
  pattern       = "main"

  required_linear_history = true

  required_pull_request_reviews {
    dismiss_stale_reviews      = true
    require_last_push_approval = false
    required_approving_review_count = 0
  }
}
