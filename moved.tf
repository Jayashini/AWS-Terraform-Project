moved {
  from = aws_vpc.main
  to   = module.vpc.aws_vpc.main
}

moved {
  from = aws_internet_gateway.main
  to   = module.vpc.aws_internet_gateway.main
}

moved {
  from = aws_subnet.public_a
  to   = module.vpc.aws_subnet.public_a
}

moved {
  from = aws_subnet.public_b
  to   = module.vpc.aws_subnet.public_b
}

moved {
  from = aws_subnet.private_a
  to   = module.vpc.aws_subnet.private_a
}

moved {
  from = aws_subnet.private_b
  to   = module.vpc.aws_subnet.private_b
}

moved {
  from = aws_route_table.public
  to   = module.vpc.aws_route_table.public
}

moved {
  from = aws_route_table.private
  to   = module.vpc.aws_route_table.private
}

moved {
  from = aws_route_table_association.public_a
  to   = module.vpc.aws_route_table_association.public_a
}

moved {
  from = aws_route_table_association.public_b
  to   = module.vpc.aws_route_table_association.public_b
}

moved {
  from = aws_route_table_association.private_a
  to   = module.vpc.aws_route_table_association.private_a
}

moved {
  from = aws_route_table_association.private_b
  to   = module.vpc.aws_route_table_association.private_b
}

moved {
  from = aws_eip.nat
  to   = module.vpc.aws_eip.nat
}

moved {
  from = aws_nat_gateway.main
  to   = module.vpc.aws_nat_gateway.main
}

moved {
  from = aws_security_group.alb
  to   = module.security.aws_security_group.alb
}

moved {
  from = aws_security_group.ec2
  to   = module.security.aws_security_group.ec2
}

moved {
  from = aws_instance.web
  to   = module.ec2.aws_instance.web
}

moved {
  from = aws_lb.app
  to   = module.alb.aws_lb.app
}

moved {
  from = aws_lb_target_group.web
  to   = module.alb.aws_lb_target_group.web
}

moved {
  from = aws_lb_target_group_attachment.web
  to   = module.alb.aws_lb_target_group_attachment.web
}

moved {
  from = aws_lb_listener.http
  to   = module.alb.aws_lb_listener.http
}
