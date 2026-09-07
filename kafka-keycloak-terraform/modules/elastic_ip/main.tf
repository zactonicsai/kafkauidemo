###############################################################################
# ELASTIC IP BASE MODULE
#
# Allocates a stable public IPv4 address. Allocated separately from the
# instance so the address is known before user-data is rendered.
###############################################################################

resource "aws_eip" "this" {
  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.name}-eip" })
}
