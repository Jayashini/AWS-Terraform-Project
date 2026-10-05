# Terraform AWS Project

Set the required `ami_id` variable to an Amazon Linux 2023 x86_64 AMI ID
available in the configured AWS region. You can find the ID in the AWS EC2
console by selecting an Amazon Linux 2023 image. Since Terraform uses the
provided ID directly, selecting the AMI does not require
`ssm:GetParameter` or `ec2:DescribeImages`.

For example, add this to `terraform.tfvars`, replacing the value with the
actual AMI ID for your region:

```hcl
ami_id = "ami-0123456789abcdef0"
```