# ECS task execution role
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

resource "aws_iam_role_policy_attachment" "ecs_task_exec_ecr" {
  role       = aws_iam_role.ecs_task_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# CodeBuild
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

resource "aws_iam_role_policy" "codebuild_inline" {
  name = "${var.project_name}-codebuild-policy"
  role = aws_iam_role.codebuild.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["ecr:GetAuthorizationToken"],
        Resource = "*"
      },
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
      {
        Effect   = "Allow",
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        Resource = "*"
      },
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
      {
        Effect   = "Allow",
        Action   = ["iam:GetRole"],
        Resource = aws_iam_role.ecs_task_exec.arn
      }
    ]
  })
}

# CodePipeline
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

resource "aws_iam_role_policy" "codepipeline_inline" {
  name = "${var.project_name}-codepipeline-policy"
  role = aws_iam_role.codepipeline.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect   = "Allow",
        Action   = ["codebuild:BatchGetBuilds", "codebuild:StartBuild"],
        Resource = aws_codebuild_project.app.arn
      },
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
      {
        Effect = "Allow",
        Action = ["iam:PassRole"],
        Resource = [
          aws_iam_role.codebuild.arn,
          aws_iam_role.codedeploy.arn
        ]
      },
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
      {
        Effect   = "Allow",
        Action   = ["codestar-connections:UseConnection"],
        Resource = aws_codestarconnections_connection.github.arn
      }
    ]
  })
}

# CodeDeploy
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
      {
        Effect = "Allow",
        Action = [
          "codedeploy:CreateDeployment",
          "codedeploy:Get*",
          "codedeploy:List*"
        ],
        Resource = "*"
      },
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
      {
        Effect   = "Allow",
        Action   = ["cloudwatch:DescribeAlarms"],
        Resource = "*"
      },
      {
        Effect   = "Allow",
        Action   = ["sns:ListTopics"],
        Resource = "*"
      }
    ]
  })
}
