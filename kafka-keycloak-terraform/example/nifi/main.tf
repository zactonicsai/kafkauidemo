###############################################################################
# EXAMPLE: Apache NiFi launch template (+ optional instance)
#
# Renders a bootstrap script from two maps – `nifi_properties` (overrides for
# conf/nifi.properties) and `nifi_user_properties` (custom key/values written
# to a separate file and registered via nifi.variable.registry.properties) –
# and feeds it to the shared launch_template module.
###############################################################################

provider "aws" {
  region = var.region
}

# ---------------------------------------------------------------------------
# AMI lookup (Amazon Linux 2023, x86_64) unless an explicit id is supplied
# ---------------------------------------------------------------------------
data "aws_ssm_parameter" "al2023" {
  count = var.image_id == null ? 1 : 0
  name  = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_subnet" "selected" {
  id = var.subnet_id
}

# ---------------------------------------------------------------------------
# Security group – NiFi HTTPS UI + optional SSH
# ---------------------------------------------------------------------------
resource "aws_security_group" "nifi" {
  name_prefix = "${var.name}-sg-"
  description = "NiFi ${var.name}"
  vpc_id      = data.aws_subnet.selected.vpc_id

  ingress {
    description = "NiFi HTTPS UI/API"
    from_port   = local.nifi_https_port
    to_port     = local.nifi_https_port
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  dynamic "ingress" {
    for_each = var.enable_ssh ? [1] : []
    content {
      description = "SSH"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.allowed_cidr_blocks
    }
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.name}-sg" })

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# IAM instance profile – SSM Session Manager access (preferred over SSH)
# ---------------------------------------------------------------------------
resource "aws_iam_role" "nifi" {
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
  role       = aws_iam_role.nifi.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "nifi" {
  name_prefix = "${var.name}-profile-"
  role        = aws_iam_role.nifi.name
  tags        = var.tags
}

# ---------------------------------------------------------------------------
# NiFi configuration – merge defaults with caller overrides
# ---------------------------------------------------------------------------
locals {
  nifi_home = "/opt/nifi"

  # Baseline nifi.properties that a caller almost always wants to control.
  # Anything in var.nifi_properties wins over these defaults.
  nifi_properties_defaults = merge(
    {
      "nifi.web.https.host"           = "0.0.0.0"
      "nifi.web.https.port"           = "8443"
      "nifi.web.proxy.host"           = var.nifi_proxy_host
      "nifi.remote.input.socket.port" = "10000"
      "nifi.remote.input.secure"      = "true"
    },
    var.data_volume_device != "" ? {
      "nifi.flowfile.repository.directory"           = "${var.data_volume_mount}/flowfile_repository"
      "nifi.content.repository.directory.default"    = "${var.data_volume_mount}/content_repository"
      "nifi.provenance.repository.directory.default" = "${var.data_volume_mount}/provenance_repository"
      "nifi.database.directory"                      = "${var.data_volume_mount}/database_repository"
    } : {}
  )

  nifi_properties = merge(local.nifi_properties_defaults, var.nifi_properties)
  nifi_https_port = tonumber(local.nifi_properties["nifi.web.https.port"])

  user_data = templatefile("${path.module}/templates/user_data.sh.tftpl", {
    nifi_version         = var.nifi_version
    nifi_download_url    = coalesce(var.nifi_download_url, "https://archive.apache.org/dist/nifi/${var.nifi_version}/nifi-${var.nifi_version}-bin.zip")
    nifi_home            = local.nifi_home
    nifi_user            = "nifi"
    java_version         = var.java_version
    nifi_properties      = local.nifi_properties
    sensitive_props_key  = var.nifi_sensitive_props_key
    user_properties      = var.nifi_user_properties
    user_properties_file = var.nifi_user_properties_file
    single_user_username = var.nifi_single_user_username
    single_user_password = var.nifi_single_user_password
    data_device          = var.data_volume_device
    data_mount           = var.data_volume_mount
  })

  additional_volumes = var.data_volume_device == "" ? [] : [{
    device_name = var.data_volume_device
    volume_size = var.data_volume_size
    volume_type = "gp3"
    encrypted   = true
  }]
}

# ---------------------------------------------------------------------------
# Launch template (shared base module)
# ---------------------------------------------------------------------------
module "nifi_launch_template" {
  source = "../../launch_template"

  name          = var.name
  description   = "Apache NiFi ${var.nifi_version}"
  image_id      = coalesce(var.image_id, try(data.aws_ssm_parameter.al2023[0].insecure_value, null))
  instance_type = var.instance_type
  key_name      = var.key_name

  iam_instance_profile_name   = aws_iam_instance_profile.nifi.name
  subnet_id                   = var.subnet_id
  security_group_ids          = concat([aws_security_group.nifi.id], var.additional_security_group_ids)
  associate_public_ip_address = var.associate_public_ip_address

  user_data = local.user_data

  root_volume_size   = var.root_volume_size
  additional_volumes = local.additional_volumes

  enable_instance_metadata_tags = true

  tags = var.tags
  instance_tags = {
    Application = "nifi"
    NiFiVersion = var.nifi_version
  }
}

# ---------------------------------------------------------------------------
# Optional single instance from the template
# ---------------------------------------------------------------------------
module "nifi_instance" {
  source = "../../ec2_instance"
  count  = var.create_instance ? 1 : 0

  name                    = var.name
  launch_template_id      = module.nifi_launch_template.id
  launch_template_version = tostring(module.nifi_launch_template.latest_version)
  eip_allocation_id       = var.eip_allocation_id
  termination_protection  = var.termination_protection
  tags                    = var.tags
}
