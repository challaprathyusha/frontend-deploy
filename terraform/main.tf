#########deployment process using terraform,autoscaling##############
#module to create frontend server
module "frontend" {
  source  = "terraform-aws-modules/ec2-instance/aws"
  ami = data.aws_ami.ami_info.id
  name = "${var.project_name}-${var.environment}-${var.common_tags.Component}"

  instance_type          = "t3.micro"
  vpc_security_group_ids = [data.aws_ssm_parameter.frontend_sg_id.value]
  #convert stringlist to list(string) and get the first element
  subnet_id              = local.subnet_id_frontend

  tags = merge(
    var.common_tags,
    {
        Name = "${var.project_name}-${var.environment}-${var.common_tags.Component}"
    }
  )
}

#null resource doesn't create any resources in provider, it is useful to run triggers like local-exec,remote-exec,some file provisioners
#here we are using it to run remote-exec
#null resources are used to perform any configurations in the servers running in aws
resource "null_resource" "frontend" {
#this will trigger everytime when instance is created
  triggers = {
    instance_id = module.frontend.id 
  }
#connects to the frontend server using vpn 
#terraform can ssh to the server running in private subnet using vpn
  connection {
      type = "ssh"
      user = "ec2-user"
      password = "DevOps321"
      host = module.frontend.private_ip
    }

#copying file from local to frontend server using file provisioner
provisioner "file" {
    source      = "${var.common_tags.Component}.sh"
    destination = "/tmp/${var.common_tags.Component}.sh"
  }
#now the script will run in the frontend server which is going to pull ansible playbook from github and run that playbook 
provisioner "remote-exec" {
     inline = [
       "chmod +x /tmp/${var.common_tags.Component}.sh",
       "sudo sh /tmp/${var.common_tags.Component}.sh ${var.common_tags.Component} ${var.environment} ${var.app_version}"
     ]
   }
}

#resource block to stop the frontend server 
resource "aws_ec2_instance_state" "frontend" {
  instance_id = module.frontend.id
  state       = "stopped"
  #stop the serever only when null resource provisioning is completed
  depends_on = [ null_resource.frontend ]
}
#resource block to take the AMI of the frontend server
resource "aws_ami_from_instance" "frontend" {
  name               = "${var.project_name}-${var.environment}-${var.common_tags.Component}"
  source_instance_id =  module.frontend.id
  depends_on = [ aws_ec2_instance_state.frontend ]
}

#null resource and local exec to terminate the frontend server which is in stopped state
resource "null_resource" "frontend_delete" {
    triggers = {
      # this will be triggered everytime instance is created
      instance_id = module.frontend.id 
    }

#local-exec provisioner to terminate the frontend server in aws 
    provisioner "local-exec" {
        command = "aws ec2 terminate-instances --instance-ids ${module.frontend.id}"
    } 

    depends_on = [ aws_ami_from_instance.frontend ]
}

#resource block to create frontend target group
resource "aws_lb_target_group" "frontend" {
  name     = "${var.project_name}-${var.environment}-${var.common_tags.Component}"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_ssm_parameter.vpc_id.value
  health_check {
    path                = "/"
    port                = 80
    protocol            = "HTTP"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 25
    matcher             = "200-299"
  }
}

#resource block to create launch template using the frontend ami
resource "aws_launch_template" "frontend" {
  name = "${var.project_name}-${var.environment}-${var.common_tags.Component}"

  image_id = aws_ami_from_instance.frontend.id
  instance_initiated_shutdown_behavior = "terminate"
  instance_type = "t3.micro"
  vpc_security_group_ids = [data.aws_ssm_parameter.frontend_sg_id.value]
  #sets the latest version to default
  update_default_version = true
  tag_specifications {
    resource_type = "instance"

    tags = merge(
      var.common_tags,
      {
      Name = "${var.project_name}-${var.environment}-${var.common_tags.Component}"
      }
    )
  }
}

#resource block to create auto scaling group by using above launch template
resource "aws_autoscaling_group" "frontend" {
  name                      = "${var.project_name}-${var.environment}-${var.common_tags.Component}"
  max_size                  = 5
  min_size                  = 1
  health_check_grace_period = 60
  health_check_type         = "ELB"
  desired_capacity          = 1
  target_group_arns = [aws_lb_target_group.frontend.arn]
  launch_template {
    id      = aws_launch_template.frontend.id
    version = "$Latest"
  }
  vpc_zone_identifier       = split(",",data.aws_ssm_parameter.public_subnet_ids.value)

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
     triggers = ["launch_template"]
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-${var.environment}-${var.common_tags.Component}"
    propagate_at_launch = true
  }

  timeouts {
    delete = "15m"
  }

  tag {
    key                 = "Project"
    value               = "${var.project_name}"
    propagate_at_launch = true
  }
}

#resource block to create auto_scaling_policy based on CPU utilization metrics
resource "aws_autoscaling_policy" "frontend" {

  name                   = "${var.project_name}-${var.environment}-${var.common_tags.Component}"
  policy_type            = "TargetTrackingScaling"
  autoscaling_group_name = aws_autoscaling_group.frontend.name

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 80.0
  }
}

#resource block to create listener rule for application load balancer
resource "aws_lb_listener_rule" "frontend" {
  listener_arn = data.aws_ssm_parameter.web_alb_listener_arn_https.value
  priority     = 100 # less number will be first validated

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.frontend.arn
  }

  condition {
    host_header {
      values = ["web-${var.environment}.${var.zone_name}"]
    }
  }
}