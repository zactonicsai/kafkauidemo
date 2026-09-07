###############################################################################
# LAUNCH TEMPLATE BASE MODULE
#
# Opinionated defaults for a hardened single-NIC instance: IMDSv2 required,
# encrypted gp3 root volume, instance profile, user-data. Everything is
# overridable through variables so the same module serves Keycloak, Kafka or
# any other workload.
###############################################################################

resource "aws_launch_template" "this" {
  name_prefix            = "${var.name}-"
  description            = var.description
  image_id               = var.image_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  update_default_version = var.update_default_version
  ebs_optimized          = var.ebs_optimized

  dynamic "iam_instance_profile" {
    for_each = var.iam_instance_profile_name == null ? [] : [1]
    content {
      name = var.iam_instance_profile_name
    }
  }

  network_interfaces {
    device_index                = 0
    associate_public_ip_address = var.associate_public_ip_address
    delete_on_termination       = true
    subnet_id                   = var.subnet_id
    security_groups             = var.security_group_ids
  }

  user_data = var.user_data == null ? null : base64encode(var.user_data)

  block_device_mappings {
    device_name = var.root_device_name

    ebs {
      volume_type           = var.root_volume_type
      volume_size           = var.root_volume_size
      iops                  = var.root_volume_iops
      throughput            = var.root_volume_throughput
      encrypted             = var.root_volume_encrypted
      kms_key_id            = var.root_volume_kms_key_id
      delete_on_termination = true
    }
  }

  dynamic "block_device_mappings" {
    for_each = var.additional_volumes
    content {
      device_name = block_device_mappings.value.device_name

      ebs {
        volume_type           = block_device_mappings.value.volume_type
        volume_size           = block_device_mappings.value.volume_size
        encrypted             = block_device_mappings.value.encrypted
        delete_on_termination = block_device_mappings.value.delete_on_termination
      }
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = var.require_imdsv2 ? "required" : "optional"
    http_put_response_hop_limit = var.metadata_hop_limit
    instance_metadata_tags      = var.enable_instance_metadata_tags ? "enabled" : "disabled"
  }

  monitoring {
    enabled = var.detailed_monitoring
  }

  tag_specifications {
    resource_type = "instance"
    tags          = merge(var.tags, var.instance_tags, { Name = "${var.name}-ec2" })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(var.tags, var.volume_tags, { Name = "${var.name}-root" })
  }

  tags = merge(var.tags, { Name = "${var.name}-launch-template" })
}
