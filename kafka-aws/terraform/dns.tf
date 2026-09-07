# Route 53 hosted zone + ACM certificate (free) validated by DNS.
# NOTE: the certificate can only validate AFTER you point your registrar's
# name servers at this zone. scripts/create.sh handles that in two phases.

resource "aws_route53_zone" "main" {
  name    = var.domain_name
  comment = "${var.project} hosted zone"
}

resource "aws_acm_certificate" "cert" {
  domain_name               = local.keycloak_host
  subject_alternative_names = [local.kafka_ui_host]
  validation_method         = "DNS"
  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cert.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }
  zone_id         = aws_route53_zone.main.zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 60
  records         = [each.value.record]
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "cert" {
  certificate_arn         = aws_acm_certificate.cert.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

resource "aws_route53_record" "keycloak" {
  zone_id = aws_route53_zone.main.zone_id
  name    = local.keycloak_host
  type    = "A"
  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "kafka_ui" {
  zone_id = aws_route53_zone.main.zone_id
  name    = local.kafka_ui_host
  type    = "A"
  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}
