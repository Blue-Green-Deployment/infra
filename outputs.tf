output "ecr_repository_url" { value = aws_ecr_repository.app.repository_url }
output "codebuild_project_name" { value = aws_codebuild_project.app.name }

#output "alb_dns_name"       { value = aws_lb.app_alb.dns_name }
#output "service_name"       { value = aws_ecs_service.app.name }
#output "cluster_name"       { value = aws_ecs_cluster.this.name }
#output "ecr_repository_url" { value = aws_ecr_repository.app.repository_url }
