# Trust policy: only this one service account in this one namespace can assume the role through the cluster OIDC provider.
data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.namespace}:${var.service_account}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# The IAM role a pod assumes through its Kubernetes service account (no long-lived credentials).
resource "aws_iam_role" "this" {
  name               = var.name
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

# Least-privilege inline permissions for the role (skipped when none are given).
resource "aws_iam_role_policy" "inline" {
  count = var.policy_json == null ? 0 : 1

  name   = "${var.name}-inline"
  role   = aws_iam_role.this.id
  policy = var.policy_json
}

# Optional AWS managed policies attached to the role.
resource "aws_iam_role_policy_attachment" "managed" {
  for_each = toset(var.managed_policy_arns)

  role       = aws_iam_role.this.name
  policy_arn = each.value
}
