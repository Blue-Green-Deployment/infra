variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "swiggy-clone"
}

variable "vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}

variable "az_count" {
  type    = number
  default = 2
}

variable "public_subnet_cidrs" {
  type    = list(string)
  default = ["10.20.0.0/24", "10.20.1.0/24"]
}

variable "private_subnet_cidrs" {
  type    = list(string)
  default = ["10.20.10.0/24", "10.20.11.0/24"]
}

#######################################
##### GitHub/CodePipeline inputs ######
#######################################

variable "github_owner" {
  type = string
}

variable "github_repo" {
  type = string
}

variable "github_branch" {
  type    = string
  default = "main"
}

variable "codestar_connection_name" {
  type    = string
  default = "github-connection"
}

#############################
#### Container settings #####
#############################

variable "container_port" {
  type    = number
  default = 8080
}

variable "cpu" {
  type    = number
  default = 256
}
variable "memory" {
  type    = number
  default = 512
}

#################################
#### Optional Sonar settings ####
#################################

variable "sonar_host_url" {
  type    = string
  default = ""
}
variable "sonar_project_key" {
  type    = string
  default = ""
}
variable "ssm_sonar_token_parameter" {
  type    = string
  default = "/cicd/sonar/sonar-token"
}
