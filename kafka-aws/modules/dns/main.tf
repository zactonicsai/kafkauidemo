# Route 53 hosted zone + DNS-validated ACM certificate covering the given hostnames.
resource "aws_route53_zone" "this" {
  name    = var.domain_name
  comment = "${var.project} hosted zone"
}

resource "aws_acm_certificate" "this" {
  domain_name               = var.certificate_hosts[0]
  subject_alternative_names = slice(var.certificate_hosts, 1, length(var.certificate_hosts))
  validation_method         = "DNS"
  lifecycle { create_before_destroy = true }
}

resource "aws_route53_record" "validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name = dvo.resource_record_name, record = dvo.resource_record_value, type = dvo.resource_record_type
    }
  }
  zone_id         = aws_route53_zone.this.zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in aws_route53_record.validation : r.fqdn]
}
