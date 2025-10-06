# Infrastructure – Blue/Green on ECS (Terraform)

This folder provisions a complete blue/green deployment pipeline on AWS for a single ECS Fargate service. It creates the network stack, ECR, ALB + target groups, ECS cluster/service, and a CI/CD pipeline (CodePipeline + CodeBuild + CodeDeploy blue/green for ECS).

## Overview
- VPC with public/private subnets and NAT.
- ALB with two target groups (blue/green) and HTTP listener on port 80.
- ECS Fargate cluster and service controlled by CodeDeploy (blue/green).
- ECR repository to store the application image.
- CodePipeline with stages: Source (GitHub via CodeStar Connections) → Build (CodeBuild) → Deploy (CodeDeploy to ECS).

## Prerequisites
- Terraform >= 1.5 and AWS credentials configured (account/region with sufficient permissions).
- An active CodeStar Connection to GitHub (Developer Tools → Connections). Note the connection name you plan to use.
- An application repository that produces the following artifacts at its root during build:
  - `appspec.yaml` with `TaskDefinition: "<TASK_DEFINITION>"`, `ContainerName: swiggy`, `ContainerPort: 3000`.
  - `taskdef.json` describing the ECS task (family `swiggy-clone`, container `swiggy`, port 3000). The build should update the image to the pushed ECR tag and set `executionRoleArn` to the role created here (`<project>-ecsTaskExecutionRole`).

## Configuration
Edit or override variables in `infra/variables.tf` when applying:
- `region` (default `us-east-1`).
- `project_name` (default `swiggy-clone`).
- `github_owner`, `github_repo`, `github_branch` to point to your app repo and branch.
- `container_port` (default `3000`) and task `cpu`/`memory`.
- `desired_count` (default `1`).

You can override at apply time, for example:
- `terraform apply -var 'github_owner=my-org' -var 'github_repo=my-app' -var 'github_branch=main' -var 'project_name=swiggy-clone'`

## What Terraform Creates
- IAM roles:
  - CodeBuild role with ECR/Logs/SSM access.
  - CodePipeline role with permissions to use CodeStar Connections, read/write artifacts, and `ecs:RegisterTaskDefinition` + `iam:PassRole` for ECS execution role.
  - CodeDeploy role with permissions to manage ECS task sets and ALB listeners/rules during traffic shifting.
- ECR repository named after `project_name`.
- ALB (`<project>-alb`) + two target groups (`<project>-tg-blue` / `green`).
- ECS cluster and service (`<project>-service`) using container `swiggy` on port `container_port`.
- CodePipeline (`<project>-pipeline`) with provider `CodeDeployToECS` configured to read templates from the build artifact:
  - `TaskDefinitionTemplatePath = taskdef.json`
  - `AppSpecTemplatePath = appspec.yaml`

## Apply
1) Initialize providers and modules:
- `terraform init`
2) Review planned changes:
- `terraform plan`
3) Create/update the stack:
- `terraform apply`

Outputs include the pipeline name and the ALB DNS name. Use the ALB DNS to validate the service after deploys.

## CI/CD Flow
1) Source: CodeStar Connections watches your GitHub repo/branch and triggers on push.
2) Build: CodeBuild logs into ECR, builds and pushes `<project>:latest`, and rewrites `taskdef.json` with the correct `executionRoleArn` and image. It publishes `appspec.yaml` and `taskdef.json` as pipeline artifacts.
3) Deploy: CodePipeline registers the task definition from `taskdef.json` and replaces the token `<TASK_DEFINITION>` inside `appspec.yaml`. CodeDeploy creates a new task set (green), validates health behind the second target group, and shifts traffic.

## Verifying
- Open the ALB DNS from Terraform outputs to see the app.
- In CodeDeploy, check the deployment status and events for health checks and traffic shift.
- In ECS, verify the primary task set switches between blue/green over time.

## Troubleshooting
- INVALID_REVISION (AppSpec):
  - Ensure `appspec.yaml` uses `TaskDefinition: "<TASK_DEFINITION>"` (with quotes) when using provider `CodeDeployToECS`.
  - `ContainerName` and `ContainerPort` in `appspec.yaml` must match the container name/port in the task definition and the service.
- Unauthorized `ecs:RegisterTaskDefinition`:
  - The CodePipeline role must allow `ecs:RegisterTaskDefinition` and `iam:PassRole` for the ECS execution role (`<project>-ecsTaskExecutionRole`).
- Health check failures:
  - Ensure your container actually listens on `container_port` (default 3000) and the ALB target groups point to the same port; adjust the health check path if your app does not serve `/`.
- Pipeline does not trigger on push:
  - Verify the CodeStar Connection is connected to the right repo/branch and the variables `github_owner`, `github_repo`, `github_branch` match. Re-apply Terraform if you change them.

## Cleaning Up
- To destroy all resources (careful – deletes the ECR repo and artifacts bucket):
- `terraform destroy`

## Notes
- Costs: this stack provisions public ALB, NAT, and Fargate tasks which incur charges while running.
- Security: restrict IAM policies further if needed (e.g., limit `ecs:RegisterTaskDefinition` to the specific family ARN).

