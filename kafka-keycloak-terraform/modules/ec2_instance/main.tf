###############################################################################
# EC2 INSTANCE BASE MODULE
#
# Launches one instance from a launch template and optionally binds an
# existing Elastic IP allocation to it.
###############################################################################

resource "aws_instance" "this" {
  launch_template {
    id      = var.launch_template_id
    version = var.launch_template_version
  }

  disable_api_termination = var.termination_protection

  tags = merge(var.tags, { Name = "${var.name}-ec2" })
}

resource "aws_eip_association" "this" {
  count = var.eip_allocation_id == null ? 0 : 1

  instance_id   = aws_instance.this.id
  allocation_id = var.eip_allocation_id
}
