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
      name = "CONTAINER_PORT" 
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
  }
  logs_config {
    cloudwatch_logs {
      group_name = "/codebuild/${var.project_name}"
    }
  }
}
