terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# GitHub OIDC Provider (Primary)
resource "aws_iam_openid_connect_provider" "github" {
  count = var.enable_github_oidc ? 1 : 0
  
  url = "https://token.actions.githubusercontent.com"
  
  client_id_list = [
    "sts.amazonaws.com"
  ]
  
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]
  
  tags = {
    Name        = "GitHub-OIDC-${var.environment}"
    Environment = var.environment
    Purpose     = "GitHub Actions OIDC authentication"
  }
}

# GitLab OIDC Provider (Alternative 1) 
resource "aws_iam_openid_connect_provider" "gitlab" {
  count = var.enable_gitlab_oidc ? 1 : 0
  
  url = "https://gitlab.com"
  
  client_id_list = [
    "sts.amazonaws.com"
  ]
  
  thumbprint_list = [
    "7e04de896a3e666ef200ce15c3450d6c5d46adc5"
  ]
  
  tags = {
    Name        = "GitLab-OIDC-${var.environment}"
    Environment = var.environment 
    Purpose     = "GitLab CI OIDC authentication"
  }
}

# Custom OIDC Provider (Alternative 2 - Keycloak/Self-hosted)
resource "aws_iam_openid_connect_provider" "custom" {
  count = var.enable_custom_oidc ? 1 : 0
  
  url = var.custom_oidc_url
  
  client_id_list = var.custom_oidc_client_ids
  
  thumbprint_list = var.custom_oidc_thumbprints
  
  tags = {
    Name        = "Custom-OIDC-${var.environment}"
    Environment = var.environment
    Purpose     = "Self-hosted OIDC authentication"
  }
}

# Data sources for trust policy conditions
locals {
  # GitHub repository conditions for different orgs
  github_repo_conditions = var.enable_github_oidc ? [
    for org in var.github_organizations : {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${org}/*:*"]
    }
  ] : []
  
  # GitLab project conditions  
  gitlab_project_conditions = var.enable_gitlab_oidc ? [
    for project in var.gitlab_projects : {
      test     = "StringLike"
      variable = "gitlab.com:sub"
      values   = ["project_path:${project}:*"]
    }
  ] : []
}

# Trust policy document for GitHub OIDC
data "aws_iam_policy_document" "github_oidc_trust" {
  count = var.enable_github_oidc ? 1 : 0
  
  statement {
    effect = "Allow"
    
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }
    
    actions = ["sts:AssumeRoleWithWebIdentity"]
    
    dynamic "condition" {
      for_each = local.github_repo_conditions
      content {
        test     = condition.value.test
        variable = condition.value.variable
        values   = condition.value.values
      }
    }
    
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# Trust policy document for GitLab OIDC
data "aws_iam_policy_document" "gitlab_oidc_trust" {
  count = var.enable_gitlab_oidc ? 1 : 0
  
  statement {
    effect = "Allow"
    
    principals {
      type        = "Federated" 
      identifiers = [aws_iam_openid_connect_provider.gitlab[0].arn]
    }
    
    actions = ["sts:AssumeRoleWithWebIdentity"]
    
    dynamic "condition" {
      for_each = local.gitlab_project_conditions
      content {
        test     = condition.value.test
        variable = condition.value.variable
        values   = condition.value.values
      }
    }
    
    condition {
      test     = "StringEquals"
      variable = "gitlab.com:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

# Trust policy document for Custom OIDC
data "aws_iam_policy_document" "custom_oidc_trust" {
  count = var.enable_custom_oidc ? 1 : 0
  
  statement {
    effect = "Allow"
    
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.custom[0].arn]
    }
    
    actions = ["sts:AssumeRoleWithWebIdentity"]
    
    dynamic "condition" {
      for_each = var.custom_oidc_conditions
      content {
        test     = condition.value.test
        variable = condition.value.variable
        values   = condition.value.values
      }
    }
  }
}

# Combined trust policy for multi-provider roles
data "aws_iam_policy_document" "multi_provider_trust" {
  dynamic "statement" {
    for_each = var.enable_github_oidc ? [1] : []
    content {
      effect = "Allow"
      
      principals {
        type        = "Federated"
        identifiers = [aws_iam_openid_connect_provider.github[0].arn]
      }
      
      actions = ["sts:AssumeRoleWithWebIdentity"]
      
      dynamic "condition" {
        for_each = local.github_repo_conditions
        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
      
      condition {
        test     = "StringEquals"
        variable = "token.actions.githubusercontent.com:aud"
        values   = ["sts.amazonaws.com"]
      }
    }
  }
  
  dynamic "statement" {
    for_each = var.enable_gitlab_oidc ? [1] : []
    content {
      effect = "Allow"
      
      principals {
        type        = "Federated"
        identifiers = [aws_iam_openid_connect_provider.gitlab[0].arn]
      }
      
      actions = ["sts:AssumeRoleWithWebIdentity"]
      
      dynamic "condition" {
        for_each = local.gitlab_project_conditions
        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
      
      condition {
        test     = "StringEquals"
        variable = "gitlab.com:aud"
        values   = ["sts.amazonaws.com"]
      }
    }
  }
  
  dynamic "statement" {
    for_each = var.enable_custom_oidc ? [1] : []
    content {
      effect = "Allow"
      
      principals {
        type        = "Federated"
        identifiers = [aws_iam_openid_connect_provider.custom[0].arn]
      }
      
      actions = ["sts:AssumeRoleWithWebIdentity"]
      
      dynamic "condition" {
        for_each = var.custom_oidc_conditions
        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }
}