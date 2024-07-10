variable "project_name" {
    type = string
    default = "expense"
  
}

variable "environment" {
    type = string
    default = "dev"
  
}

#common tags for frontend server
variable "common_tags" {
    type = map
    default = {
        Project = "Expense"
        Terraform = "true"
        Environment = "dev"
        Component = "frontend"
    }

}

variable "zone_name" {
    type = string
    default = "expensesnote.site"
  
}

variable "app_version" {
  
}