locals {
  common_tags = merge(
    {
      Project = var.project_name
    },
    var.tags
  )
}
