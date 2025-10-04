resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/codebuild/${var.project_name}"
  retention_in_days = 30

  tags = merge(local.common_tags, {
    Name = "/codebuild/${var.project_name}"
  })
}

resource "aws_codebuild_project" "app" {
  name          = "${var.project_name}-build"
  service_role  = aws_iam_role.codebuild.arn
  build_timeout = 30

  source {
    type      = "CODEPIPELINE"
    buildspec = file("${path.module}/files/buildspec.yml")
  }
  artifacts { type = "CODEPIPELINE" }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true

    environment_variable {
      name  = "ECR_REPO"
      value = aws_ecr_repository.app.repository_url
    }
    environment_variable {
      name  = "CONTAINER_PORT"
      value = tostring(var.container_port)
    }
    environment_variable {
      name  = "CPU"
      value = tostring(var.cpu)
    }
    environment_variable {
      name  = "MEMORY"
      value = tostring(var.memory)
    }
    environment_variable {
      name  = "PROJECT_NAME"
      value = var.project_name
    }

    #### Sonar variables ####
    #########################  
    environment_variable {
      name  = "SONAR_HOST_URL"
      value = var.sonar_host_url
    }
    environment_variable {
      name  = "SONAR_PROJECT_KEY"
      value = var.sonar_project_key
    }
    environment_variable {
      name  = "SONAR_TOKEN"
      type  = "PARAMETER_STORE"
      value = var.ssm_sonar_token_parameter
    }
  }
  logs_config {
    cloudwatch_logs {
      group_name = aws_cloudwatch_log_group.codebuild.name
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.project_name}-build"
  })
}
