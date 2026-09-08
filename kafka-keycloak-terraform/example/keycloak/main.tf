###############################################################################
# EXAMPLE: Keycloak (Docker) launch template + internal ALB
#
# Fully private: no public IPs, ALB is internal-only, ingress limited to
# allowed_cidr_blocks. Keycloak configuration is driven by two maps –
# `keycloak_env` (KC_* environment options) and `keycloak_user_properties`
# (extra keycloak.conf entries) – rendered into the launch template user data.
###############################################################################

provider "aws" {
  region = var.region
}

data "aws_ssm_parameter" "al2023" {
  count = var.image_id == null ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_subnet" "instance" {
  id = var.instance_subnet_id
}

# ---------------------------------------------------------------------------
# Security groups
# ---------------------------------------------------------------------------
resource "aws_security_group" "alb" {
  name_prefix = "${var.name}-alb-"
  description = "Internal ALB for Keycloak ${var.name}"
  vpc_id      = data.aws_subnet.instance.vpc_id

  ingress {
    description = "Keycloak via ALB"
    from_port   = local.listener_port
    to_port     = local.listener_port
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-alb-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "instance" {
  name_prefix = "${var.name}-ec2-"
  description = "Keycloak instance ${var.name} – ALB only"
  vpc_id      = data.aws_subnet.instance.vpc_id

  ingress {
    description     = "Keycloak HTTP from ALB"
    from_port       = var.keycloak_http_port
    to_port         = var.keycloak_http_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  ingress {
    description     = "Keycloak management/health from ALB"
    from_port       = var.keycloak_management_port
    to_port         = var.keycloak_management_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    description = "Outbound (image pulls, DB, SSM) – route via NAT/VPC endpoints"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-ec2-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# IAM – SSM Session Manager (no SSH / no public access required)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "keycloak" {
  name_prefix = "${var.name}-role-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.keycloak.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "keycloak" {
  name_prefix = "${var.name}-profile-"
  role        = aws_iam_role.keycloak.name
  tags        = var.tags
}

# ---------------------------------------------------------------------------
# Keycloak configuration – defaults merged with caller overrides
# ---------------------------------------------------------------------------
locals {
  use_https     = var.certificate_arn != null
  listener_port = local.use_https ? 443 : 80
  scheme        = local.use_https ? "https" : "http"

  keycloak_env_defaults = merge(
    {
      # Behind a TLS-terminating / forwarding proxy
      KC_HTTP_ENABLED         = "true"
      KC_HTTP_PORT            = "8080"
      KC_PROXY_HEADERS        = "xforwarded"
      KC_HOSTNAME             = var.keycloak_hostname
      KC_HOSTNAME_STRICT      = "true"
      KC_HEALTH_ENABLED       = "true"
      KC_METRICS_ENABLED      = "true"
      KC_HTTP_MANAGEMENT_PORT = "9000"
    },
    var.db_url != null ? {
      KC_DB          = var.db_vendor
      KC_DB_URL      = var.db_url
      KC_DB_USERNAME = var.db_username
    } : {}
  )

  keycloak_env = merge(local.keycloak_env_defaults, var.keycloak_env)

  user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    image           = var.keycloak_image
    keycloak_env    = local.keycloak_env
    user_properties = var.keycloak_user_properties
    extra_args      = var.keycloak_extra_args
    admin_username  = var.keycloak_admin_username
    admin_password  = var.keycloak_admin_password
    db_password     = var.db_password
    http_port       = var.keycloak_http_port
    management_port = var.keycloak_management_port
  })
}

# ---------------------------------------------------------------------------
# Launch template (shared base module) – private only
# ---------------------------------------------------------------------------
module "keycloak_launch_template" {
  source = "../../launch_template"

  name          = var.name
  description   = "Keycloak ${var.keycloak_image}"
  image_id      = coalesce(var.image_id, try(data.aws_ssm_parameter.al2023[0].insecure_value, null))
  instance_type = var.instance_type
  key_name      = var.key_name

  iam_instance_profile_name   = aws_iam_instance_profile.keycloak.name
  subnet_id                   = var.instance_subnet_id
  security_group_ids          = concat([aws_security_group.instance.id], var.additional_security_group_ids)
  associate_public_ip_address = false

  user_data = local.user_data

  root_volume_size              = var.root_volume_size
  metadata_hop_limit            = 2 # container on the host needs IMDS
  enable_instance_metadata_tags = true

  tags = var.tags
  instance_tags = {
    Application   = "keycloak"
    KeycloakImage = var.keycloak_image
  }
}

# ---------------------------------------------------------------------------
# Internal Application Load Balancer + target group
# ---------------------------------------------------------------------------
resource "aws_lb" "keycloak" {
  name_prefix        = substr("${var.name}-", 0, 6)
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.lb_subnet_ids

  drop_invalid_header_fields = true
  idle_timeout               = var.lb_idle_timeout

  tags = merge(var.tags, { Name = "${var.name}-alb" })
}

resource "aws_lb_target_group" "keycloak" {
  name_prefix = substr("${var.name}-", 0, 6)
  vpc_id      = data.aws_subnet.instance.vpc_id
  port        = var.keycloak_http_port
  protocol    = "HTTP"
  target_type = "instance"

  deregistration_delay = 30

  health_check {
    enabled             = true
    protocol            = "HTTP"
    port                = tostring(var.keycloak_management_port)
    path                = "/health/ready"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  stickiness {
    type            = "lb_cookie"
    cookie_duration = 3600
    enabled         = true
  }

  tags = merge(var.tags, { Name = "${var.name}-tg" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "keycloak" {
  load_balancer_arn = aws_lb.keycloak.arn
  port              = local.listener_port
  protocol          = local.use_https ? "HTTPS" : "HTTP"
  ssl_policy        = local.use_https ? var.ssl_policy : null
  certificate_arn   = var.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.keycloak.arn
  }

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Optional single instance from the template, registered with the TG
# ---------------------------------------------------------------------------
module "keycloak_instance" {
  source = "../../ec2_instance"
  count  = var.create_instance ? 1 : 0

  name                    = var.name
  launch_template_id      = module.keycloak_launch_template.id
  launch_template_version = tostring(module.keycloak_launch_template.latest_version)
  termination_protection  = var.termination_protection
  tags                    = var.tags
}

resource "aws_lb_target_group_attachment" "keycloak" {
  count = var.create_instance ? 1 : 0

  target_group_arn = aws_lb_target_group.keycloak.arn
  target_id        = module.keycloak_instance[0].id
  port             = var.keycloak_http_port
}
