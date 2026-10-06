module "vpc" {
  source = "./modules/vpc"

  project_name         = var.project_name
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

module "security" {
  source = "./modules/security"

  project_name = var.project_name
  vpc_id       = module.vpc.vpc_id
}

module "ec2" {
  source = "./modules/ec2"

  project_name      = var.project_name
  subnet_id         = module.vpc.private_subnet_ids[0]
  security_group_id = module.security.ec2_security_group_id

}

module "alb" {
  source = "./modules/alb"

  project_name       = var.project_name
  vpc_id             = module.vpc.vpc_id
  public_subnet_ids  = module.vpc.public_subnet_ids
  security_group_id  = module.security.alb_security_group_id
  target_instance_id = module.ec2.instance_id

}
