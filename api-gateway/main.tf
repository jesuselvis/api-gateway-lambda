resource "aws_lb" "nlb" {
  name               = "my-nlb"
  internal           = true
  load_balancer_type = "network"
  subnets            = ["subnet-0b5f62da821405724", "subnet-0101cffdbf710bf91"]
}

resource "aws_lb_target_group" "nlb_tg" {
  name     = "nlb-tg"
  port     = 80
  protocol = "TCP"
  vpc_id   = "vpc-0c8db42a63f733364"
  target_type = "alb"
   health_check {
    protocol = "HTTP"
    port     = "traffic-port"
    path     = "/health"
    interval = 30
    timeout  = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "nlb_listener" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = 80
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nlb_tg.arn
  }
}

#Configurar el ALB para EKS
resource "aws_lb" "alb" {
  name               = "my-alb"
  internal           = true
  load_balancer_type = "application"
  subnets            = ["subnet-0b5f62da821405724", "subnet-0101cffdbf710bf91"]
}

resource "aws_lb_target_group" "alb_tg" {
  name     = "alb-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = "vpc-0c8db42a63f733364"
  target_type = "instance"  # Usa "ip" si los pods tienen IPs directas, o "instance" si usas instancias EC2
  health_check {
    protocol = "HTTP"
    port     = "traffic-port"
    path     = "/health"
    interval = 30
    timeout  = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "alb_listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.alb_tg.arn
  }
}

resource "aws_lb_target_group_attachment" "alb_tg_attachment" {
  target_group_arn = aws_lb_target_group.alb_tg.arn
  target_id        = "i-043cac59fe2ff1d1b"  # Reemplaza con tu ID de instancia de EC2
  port             = 80
}

#Configurar el VPC Link con el NLB:
resource "aws_api_gateway_vpc_link" "vpc_link" {
  name = "my-vpc-link"
  target_arns = [aws_lb.nlb.arn]
}

#Definir los recursos y métodos del API Gateway:
resource "aws_api_gateway_rest_api" "dynamic_http_api" {
  name        = "BianCapability"
  description = "API gtw integracion con VPC Link"
}

resource "aws_api_gateway_resource" "payment_to_info_assoc" {
  rest_api_id = aws_api_gateway_rest_api.dynamic_http_api.id
  parent_id   = aws_api_gateway_rest_api.dynamic_http_api.root_resource_id
  path_part   = "payment-to-information-association-x"
}

resource "aws_api_gateway_resource" "internal_transfers" {
  rest_api_id = aws_api_gateway_rest_api.dynamic_http_api.id
  parent_id   = aws_api_gateway_resource.payment_to_info_assoc.id
  path_part   = "internal-transfers"
}

resource "aws_api_gateway_resource" "execute" {
  rest_api_id = aws_api_gateway_rest_api.dynamic_http_api.id
  parent_id   = aws_api_gateway_resource.internal_transfers.id
  path_part   = "execute"
}

resource "aws_api_gateway_method" "post_execute" {
  rest_api_id   = aws_api_gateway_rest_api.dynamic_http_api.id
  resource_id   = aws_api_gateway_resource.execute.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_resource" "register" {
  rest_api_id = aws_api_gateway_rest_api.dynamic_http_api.id
  parent_id   = aws_api_gateway_resource.internal_transfers.id
  path_part   = "register"
}

resource "aws_api_gateway_method" "post_register" {
  rest_api_id   = aws_api_gateway_rest_api.dynamic_http_api.id
  resource_id   = aws_api_gateway_resource.register.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_resource" "update" {
  rest_api_id = aws_api_gateway_rest_api.dynamic_http_api.id
  parent_id   = aws_api_gateway_resource.internal_transfers.id
  path_part   = "update"
}

resource "aws_api_gateway_method" "patch_update" {
  rest_api_id   = aws_api_gateway_rest_api.dynamic_http_api.id
  resource_id   = aws_api_gateway_resource.update.id
  http_method   = "PATCH"
  authorization = "NONE"
}

resource "aws_api_gateway_resource" "retrieve" {
  rest_api_id = aws_api_gateway_rest_api.dynamic_http_api.id
  parent_id   = aws_api_gateway_resource.internal_transfers.id
  path_part   = "retrieve"
}

resource "aws_api_gateway_method" "get_retrieve" {
  rest_api_id   = aws_api_gateway_rest_api.dynamic_http_api.id
  resource_id   = aws_api_gateway_resource.retrieve.id
  http_method   = "GET"
  authorization = "NONE"
}

#Configurar las integraciones para usar el VPC Link:
resource "aws_api_gateway_integration" "post_execute_integration" {
  rest_api_id             = aws_api_gateway_rest_api.dynamic_http_api.id
  resource_id             = aws_api_gateway_resource.execute.id
  http_method             = aws_api_gateway_method.post_execute.http_method
  integration_http_method = "POST"
  type                    = "HTTP_PROXY"
  uri                     = "http://internal-k8s-default-ingressa-4fbe709689-219581266.us-east-1.elb.amazonaws.com/execute"  # Reemplazar con el endpoint de tu servicio interno en EKS
  connection_type         = "VPC_LINK"
  connection_id           = aws_api_gateway_vpc_link.vpc_link.id
}

resource "aws_api_gateway_integration" "post_register_integration" {
  rest_api_id             = aws_api_gateway_rest_api.dynamic_http_api.id
  resource_id             = aws_api_gateway_resource.register.id
  http_method             = aws_api_gateway_method.post_register.http_method
  integration_http_method = "POST"
  type                    = "HTTP_PROXY"
  uri                     = "http://internal-k8s-default-ingressa-4fbe709689-219581266.us-east-1.elb.amazonaws.com/register"  # "http://${aws_lb.alb.dns_name}/execute" Reemplazar con el endpoint de tu servicio interno en EKS
  connection_type         = "VPC_LINK"
  connection_id           = aws_api_gateway_vpc_link.vpc_link.id
}

resource "aws_api_gateway_integration" "patch_update_integration" {
  rest_api_id             = aws_api_gateway_rest_api.dynamic_http_api.id
  resource_id             = aws_api_gateway_resource.update.id
  http_method             = aws_api_gateway_method.patch_update.http_method
  integration_http_method = "PATCH"
  type                    = "HTTP_PROXY"
  uri                     = "http://internal-k8s-default-ingressa-4fbe709689-219581266.us-east-1.elb.amazonaws.com/update"  # Reemplazar con el endpoint de tu servicio interno en EKS
  connection_type         = "VPC_LINK"
  connection_id           = aws_api_gateway_vpc_link.vpc_link.id
}

resource "aws_api_gateway_integration" "get_retrieve_integration" {
  rest_api_id             = aws_api_gateway_rest_api.dynamic_http_api.id
  resource_id             = aws_api_gateway_resource.retrieve.id
  http_method             = aws_api_gateway_method.get_retrieve.http_method
  integration_http_method = "GET"
  type                    = "HTTP_PROXY"
  uri                     = "http://internal-k8s-default-ingressa-4fbe709689-219581266.us-east-1.elb.amazonaws.com/retrieve"  # Reemplazar con el endpoint de tu servicio interno en EKS
  connection_type         = "VPC_LINK"
  connection_id           = aws_api_gateway_vpc_link.vpc_link.id
}

#Configurar el despliegue del API Gateway:
resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on = [
    aws_api_gateway_integration.post_execute_integration,
    aws_api_gateway_integration.post_register_integration,
    aws_api_gateway_integration.patch_update_integration,
    aws_api_gateway_integration.get_retrieve_integration,
  ]
  rest_api_id = aws_api_gateway_rest_api.dynamic_http_api.id
  stage_name  = "default"
}

resource "aws_api_gateway_stage" "dev_stage" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.dynamic_http_api.id
  stage_name    = "dev"
}

resource "aws_api_gateway_stage" "prod_stage" {
  deployment_id = aws_api_gateway_deployment.api_deployment.id
  rest_api_id   = aws_api_gateway_rest_api.dynamic_http_api.id
  stage_name    = "prod"
}
