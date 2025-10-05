#############################################
# Identity helpers
#############################################
data "aws_caller_identity" "current" {}

#############################################
# ECS Task Execution Role (for Fargate tasks)
#############################################
data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_exec" {
  name               = "${var.project_name}-ecsTaskExecutionRole"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-ecsTaskExecutionRole"
    Role = "ecs-task-exec"
  })
}

# AWS managed policy with ECR pull, logs, and secrets access for task execution
resource "aws_iam_role_policy_attachment" "ecs_task_exec_ecr" {
  role       = aws_iam_role.ecs_task_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

#############################################
# CodeBuild Role
#############################################
data "aws_iam_policy_document" "codebuild_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codebuild" {
  name               = "${var.project_name}-codebuild-role"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume.json

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-codebuild-role"
    Role = "codebuild"
  })
}

# Inline policy for ECR, logs, SSM (Sonar token), and reading ECS exec role ARN
resource "aws_iam_role_policy" "codebuild_inline" {
  name = "${var.project_name}-codebuild-policy"
  role = aws_iam_role.codebuild.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # ECR auth token
      {
        Effect   = "Allow",
        Action   = ["ecr:GetAuthorizationToken"],
        Resource = "*"
      },
      # ECR repo-specific actions (push/pull)
      {
        Effect = "Allow",
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:BatchGetImage",
          "ecr:CompleteLayerUpload",
          "ecr:DescribeRepositories",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart"
        ],
        Resource = aws_ecr_repository.app.arn
      },
      # CloudWatch Logs for build logs
      {
        Effect   = "Allow",
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        Resource = "*"
      },
      # Read Sonar token from SSM Parameter Store
      {
        Effect = "Allow",
        Action = ["ssm:GetParameter", "ssm:GetParameters"],
        Resource = format(
          "arn:aws:ssm:%s:%s:parameter/%s",
          var.region,
          data.aws_caller_identity.current.account_id,
          trim(var.ssm_sonar_token_parameter, "/")
        )
      },
      # Optional: if SSM parameter is SecureString with a CMK, attach a KMS policy separately.
      # See "Optional KMS policies" section below.

      # Read ECS Task Execution Role ARN during build
      {
        Effect   = "Allow",
        Action   = ["iam:GetRole"],
        Resource = aws_iam_role.ecs_task_exec.arn
      },
      # Helpful to introspect account id in scripts (non-sensitive)
      {
        Effect   = "Allow",
        Action   = ["sts:GetCallerIdentity"],
        Resource = "*"
      }
    ]
  })
}

# S3 artifacts (read/write) for CodeBuild -> CodePipeline artifact bucket
data "aws_iam_policy_document" "codebuild_s3_artifacts" {
  # Bucket-level
  statement {
    sid = "S3BucketMetadata"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListBucketMultipartUploads"
    ]
    resources = [aws_s3_bucket.artifacts.arn]
  }

  # Object-level
  statement {
    sid = "S3ObjectRW"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts"
      # "s3:DeleteObject",  # enable if you plan to delete artifacts
      # "s3:PutObjectAcl"   # only if the bucket policy/ownership requires ACLs
    ]
    resources = ["${aws_s3_bucket.artifacts.arn}/*"]
  }
}

resource "aws_iam_policy" "codebuild_s3_artifacts" {
  name   = "${var.project_name}-codebuild-s3-artifacts"
  policy = data.aws_iam_policy_document.codebuild_s3_artifacts.json
}

resource "aws_iam_role_policy_attachment" "codebuild_s3_artifacts_attach" {
  role       = aws_iam_role.codebuild.name
  policy_arn = aws_iam_policy.codebuild_s3_artifacts.arn
}

# Optional: allow sending emails via SES from CodeBuild (only if used in buildspec)
# resource "aws_iam_policy" "codebuild_ses" {
#   name        = "${var.project_name}-codebuild-ses"
#   description = "Allow CodeBuild to send emails via SES"
#   policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect   = "Allow",
#         Action   = ["ses:SendEmail", "ses:SendRawEmail"],
#         Resource = "*"
#       }
#     ]
#   })
# }
# resource "aws_iam_role_policy_attachment" "attach_codebuild_ses" {
#   role       = aws_iam_role.codebuild.name
#   policy_arn = aws_iam_policy.codebuild_ses.arn
# }

#############################################
# CodePipeline Role
#############################################
data "aws_iam_policy_document" "codepipeline_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codepipeline" {
  name               = "${var.project_name}-codepipeline-role"
  assume_role_policy = data.aws_iam_policy_document.codepipeline_assume.json

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-codepipeline-role"
    Role = "codepipeline"
  })
}

# Inline policy for Pipeline -> CodeBuild, CodeDeploy, S3, and CodeStar Connections
resource "aws_iam_role_policy" "codepipeline_inline" {
  name = "${var.project_name}-codepipeline-policy"
  role = aws_iam_role.codepipeline.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # Start and get builds on the CodeBuild project
      {
        Effect   = "Allow",
        Action   = ["codebuild:BatchGetBuilds", "codebuild:StartBuild"],
        Resource = aws_codebuild_project.app.arn
      },

      # CodeDeploy - app and deployment group access
      {
        Effect = "Allow",
        Action = ["codedeploy:CreateDeployment", "codedeploy:Get*", "codedeploy:List*"],
        Resource = [
          aws_codedeploy_app.ecs.arn,
          format(
            "arn:aws:codedeploy:%s:%s:deploymentgroup:%s/%s",
            var.region,
            data.aws_caller_identity.current.account_id,
            aws_codedeploy_app.ecs.name,
            aws_codedeploy_deployment_group.ecs.deployment_group_name
          )
        ]
      },

      # CodeDeploy - DeploymentConfig read (defaults for ECS)
      {
        Effect = "Allow",
        Action = ["codedeploy:GetDeploymentConfig", "codedeploy:ListDeploymentConfigs"],
        Resource = [
          "arn:aws:codedeploy:${var.region}:${data.aws_caller_identity.current.account_id}:deploymentconfig:CodeDeployDefault.ECSAllAtOnce",
          "arn:aws:codedeploy:${var.region}:${data.aws_caller_identity.current.account_id}:deploymentconfig:CodeDeployDefault.ECSCanary10Percent5Minutes",
          "arn:aws:codedeploy:${var.region}:${data.aws_caller_identity.current.account_id}:deploymentconfig:CodeDeployDefault.ECSLinear10PercentEvery1Minutes"
          # Or use the wildcard below if you plan to create custom configs:
          # "arn:aws:codedeploy:${var.region}:${data.aws_caller_identity.current.account_id}:deploymentconfig:*"
        ]
      },

      # PassRole for the roles used in the pipeline
      {
        Effect = "Allow",
        Action = ["iam:PassRole"],
        Resource = [
          aws_iam_role.codebuild.arn,
          aws_iam_role.codedeploy.arn
        ]
      },

      # S3 artifacts (pipeline bucket) - list and object R/W
      {
        Effect   = "Allow",
        Action   = ["s3:GetBucketLocation", "s3:ListBucket"],
        Resource = aws_s3_bucket.artifacts.arn
      },
      {
        Effect   = "Allow",
        Action   = ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject"],
        Resource = "${aws_s3_bucket.artifacts.arn}/*"
      },

      # Source via CodeStar Connections (GitHub)
      {
        Effect   = "Allow",
        Action   = ["codestar-connections:UseConnection"],
        Resource = aws_codestarconnections_connection.github.arn
      },

      # CodeDeploy - allow registering the application revision
      {
        Effect   = "Allow",
        Action   = ["codedeploy:RegisterApplicationRevision"],
        Resource = aws_codedeploy_app.ecs.arn
      }
    ]
  })
}

#############################################
# CodeDeploy Role #####
#############################################
data "aws_iam_policy_document" "codedeploy_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codedeploy.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codedeploy" {
  name               = "${var.project_name}-codedeploy-role"
  assume_role_policy = data.aws_iam_policy_document.codedeploy_assume.json

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-codedeploy-role"
    Role = "codedeploy"
  })
}

resource "aws_iam_role_policy" "codedeploy_inline" {
  name = "${var.project_name}-codedeploy-policy"
  role = aws_iam_role.codedeploy.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # General CodeDeploy actions
      {
        Effect = "Allow",
        Action = [
          "codedeploy:CreateDeployment",
          "codedeploy:Get*",
          "codedeploy:List*"
        ],
        Resource = "*"
      },
      # ECS control for blue/green
      {
        Effect = "Allow",
        Action = [
          "ecs:CreateTaskSet",
          "ecs:DeleteTaskSet",
          "ecs:DescribeClusters",
          "ecs:DescribeServices",
          "ecs:DescribeTaskSets",
          "ecs:UpdateService",
          "ecs:UpdateServicePrimaryTaskSet"
        ],
        Resource = "*"
      },
      # Load balancer changes during shift
      {
        Effect = "Allow",
        Action = [
          "elasticloadbalancing:DescribeListeners",
          "elasticloadbalancing:DescribeLoadBalancers",
          "elasticloadbalancing:DescribeRules",
          "elasticloadbalancing:DescribeTargetGroups",
          "elasticloadbalancing:ModifyListener",
          "elasticloadbalancing:ModifyRule"
        ],
        Resource = "*"
      },
      # Monitoring & notifications
      {
        Effect   = "Allow",
        Action   = ["cloudwatch:DescribeAlarms"],
        Resource = "*"
      },
      {
        Effect   = "Allow",
        Action   = ["sns:ListTopics"],
        Resource = "*"
      },
      {
        Effect   = "Allow",
        Action   = ["iam:PassRole"],
        Resource = aws_iam_role.ecs_task_exec.arn
      },
      # Access pipeline artifacts for task/app specs
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ],
        Resource = "${aws_s3_bucket.artifacts.arn}/*"
      },
      {
        Effect   = "Allow",
        Action   = ["s3:GetBucketLocation"],
        Resource = aws_s3_bucket.artifacts.arn
      }
    ]
  })
}

#############################################
# Optional KMS policies (uncomment if needed)
#############################################

# If your SSM parameter (SONAR token) is SecureString with a customer-managed CMK:
# resource "aws_iam_policy" "codebuild_kms_for_ssm" {
#   name        = "${var.project_name}-codebuild-kms-for-ssm"
#   description = "Allow CodeBuild to decrypt SSM SecureString via KMS"
#   policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Action = ["kms:Decrypt", "kms:DescribeKey"],
#         Resource = "<KMS_KEY_ARN>",
#         Condition = {
#           StringEquals = {
#             "kms:ViaService" = "ssm.${var.region}.amazonaws.com"
#           }
#         }
#       }
#     ]
#   })
# }
# resource "aws_iam_role_policy_attachment" "codebuild_kms_for_ssm_attach" {
#   role       = aws_iam_role.codebuild.name
#   policy_arn = aws_iam_policy.codebuild_kms_for_ssm.arn
# }

# If your artifacts bucket is encrypted with a CMK (SSE-KMS):
# resource "aws_iam_policy" "codebuild_kms_for_s3" {
#   name        = "${var.project_name}-codebuild-kms-for-s3"
#   description = "Allow CodeBuild to use KMS key for S3 artifacts"
#   policy = jsonencode({
#     Version = "2012-10-17",
#     Statement = [
#       {
#         Effect = "Allow",
#         Action = [
#           "kms:Encrypt",
#           "kms:Decrypt",
#           "kms:ReEncrypt*",
#           "kms:GenerateDataKey*",
#           "kms:DescribeKey"
#         ],
#         Resource = "<KMS_KEY_ARN>",
#         Condition = {
#           StringEquals = {
#             "kms:ViaService" = "s3.${var.region}.amazonaws.com"
#           }
#         }
#       }
#     ]
#   })
# }
# resource "aws_iam_role_policy_attachment" "codebuild_kms_for_s3_attach" {
#   role       = aws_iam_role.codebuild.name
#   policy_arn = aws_iam_policy.codebuild_kms_for_s3.arn
# }
