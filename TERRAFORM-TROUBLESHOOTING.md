# Terraform AWS troubleshooting and recovery runbook

This runbook collects the commands used while diagnosing the S3 backend,
Terraform state, duplicate AWS resources, VPC mismatches, and the VPC quota.
It is written for PowerShell and this repository.

## Important safety notes

- Run commands from the repository root unless a command says otherwise.
- Confirm the AWS account, region, Terraform workspace, and backend before
  changing state or AWS resources.
- Resource IDs recorded during earlier troubleshooting are historical
  observations. AWS resources have since changed; always query AWS again and
  confirm each ID before using a destructive command.
- `terraform state rm` only detaches an address from Terraform state; it does
  not delete the AWS resource. It can orphan resources and is not a cleanup
  command.
- `terraform destroy` only destroys resources in the active Terraform state.
  It does not delete the S3 bucket used for the backend.
- Never delete the backend bucket or its state object when intending to clean
  up application infrastructure.
- Terraform state can contain sensitive values. Keep state backups private and
  never paste raw state contents into chat or commit them.

## 1. Confirm the AWS account, region, workspace, and backend

Use this before `init`, `plan`, `apply`, `import`, `destroy`, or any AWS
cleanup command:

```powershell
aws sts get-caller-identity
terraform workspace list
terraform workspace show
```

The backend configuration in this repository is `backend.hcl`. It currently
specifies bucket `s3-bucket-terraform-j`, key
`terraform-aws-project/terraform.tfstate`, and region `ap-southeast-1`.
Initialize or reconnect to that backend with:

```powershell
terraform init -reconfigure -backend-config="backend.hcl"
```

If you have local state that you intend to migrate to the S3 backend, use
`-migrate-state` instead of `-reconfigure`, and only after reviewing Terraform's
migration prompt:

```powershell
terraform init -backend-config="backend.hcl" -migrate-state
```

If AWS reports that a bucket is in a different region, set the backend
`region` to the bucket's actual region. Earlier AWS output established
`ap-southeast-1` for this bucket. The AWS provider region is configured
separately in Terraform variables/provider configuration.

List objects under the configured state key prefix (this lists metadata, not
the resources themselves):

```powershell
aws s3 ls s3://s3-bucket-terraform-j/terraform-aws-project/ --recursive --region ap-southeast-1
```

Use the active Terraform state to see managed resource addresses:

```powershell
terraform state list
```

Inspect an individual address from that list:

```powershell
terraform state show module.vpc.aws_vpc.main
```

The example address only works if it is present in `terraform state list`.
An empty list means the selected state/workspace contains no tracked resources;
it does not prove that AWS has no resources.

The workspace/state check made while preparing this runbook showed workspace
`default` and managed addresses for the VPC, subnets, route tables, gateways,
security groups, EC2 instance, ALB, listener, target group, and attachment.
This is only a point-in-time observation. Re-run `terraform state list` before
any cleanup; do not assume the earlier empty-state output is still accurate.

## 2. Back up remote state before state changes or a full cleanup

Use this before imports, `state rm`, state migration, or destructive cleanup:

```powershell
$backup = Join-Path $env:USERPROFILE ("terraform-state-backup-" + (Get-Date -Format "yyyyMMdd-HHmmss") + ".json")
terraform state pull | Set-Content -Path $backup -Encoding utf8
Get-Item $backup
```

Keep the generated file private. Do not upload or commit it.

## 3. Normal plan and apply workflow

After backend initialization, inspect the proposed changes before applying:

```powershell
terraform plan
terraform apply
```

Approve only when the plan matches the intended infrastructure changes. If
the plan unexpectedly replaces or destroys resources, stop and investigate.

## 4. Existing ALB or target group already exists

An `already exists` error usually means Terraform is attempting to create an
AWS resource that already exists but is not tracked at the required state
address. First check account, workspace, backend, and state:

```powershell
aws sts get-caller-identity
terraform workspace show
terraform state list
```

If the ALB or target group is already in state, do not import it again.
Investigate why the active state/configuration is trying to create it.

If the resources are not in the active state, fetch their current ARNs:

```powershell
$region = "ap-southeast-1"
$albArn = aws elbv2 describe-load-balancers --names terraform-aws-project-alb --region $region --query "LoadBalancers[0].LoadBalancerArn" --output text
$tgArn = aws elbv2 describe-target-groups --names terraform-aws-project-tg --region $region --query "TargetGroups[0].TargetGroupArn" --output text
$albArn
$tgArn
```

Confirm neither value is `None`, then import only resources that are absent
from the active state:

```powershell
terraform import module.alb.aws_lb.app $albArn
terraform import module.alb.aws_lb_target_group.web $tgArn
```

The following is the literal ALB ARN returned during earlier troubleshooting,
not a promise that this ID is still current:

```powershell
terraform import module.alb.aws_lb.app arn:aws:elasticloadbalancing:ap-southeast-1:843282289436:loadbalancer/app/terraform-aws-project-alb/163725f492988f4b
```

Do not type angle-bracket placeholders such as
`<paste-target-group-ARN-here>` into PowerShell. PowerShell treats those
characters as syntax; use the `$tgArn` variable above or paste a real ARN.

If Terraform also reports an existing listener or target-group attachment,
inspect the listener and attachment first. Only import them if they exist in
AWS and are absent from state:

```powershell
aws elbv2 describe-listeners --load-balancer-arn $albArn --region $region --output table
terraform state list
```

Listener import ID is its listener ARN. Target-group attachment import ID is
`target-group-arn,instance-id,port`. Replace the example values with values
from the current AWS output:

```powershell
terraform import module.alb.aws_lb_listener.http <listener-arn>
terraform import module.alb.aws_lb_target_group_attachment.web <target-group-arn>,<instance-id>,80
```

After importing, check the planned changes:

```powershell
terraform plan
```

## 5. Diagnose an invalid ALB security group

An `InvalidConfigurationRequest: One or more security groups are invalid`
error commonly means the security group is in a different VPC from the ALB.
Check the ALB's VPC/security groups and the Terraform-managed security group:

```powershell
aws elbv2 describe-load-balancers --names terraform-aws-project-alb --region ap-southeast-1 --query "LoadBalancers[0].{VpcId:VpcId,SecurityGroups:SecurityGroups}" --output json
terraform state show module.security.aws_security_group.alb
terraform state show module.vpc.aws_vpc.main
```

The ALB, its security group, its public subnets, and its target group must be
compatible with the same VPC. Changing only the security-group ID will not
correct a VPC mismatch. Stop applying until the intended VPC and resource
ownership are decided.

## 6. Inspect VPC resources before adoption or deletion

Set the region and VPC ID from fresh AWS output; do not assume historical IDs
are still current:

```powershell
$region = "ap-southeast-1"
$vpc = "vpc-REPLACE-WITH-VERIFIED-ID"

aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc" --region $region --output table
aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpc" --region $region --query "NatGateways[].{Id:NatGatewayId,State:State,Subnet:SubnetId}" --output table
aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$vpc" --region $region --query "NetworkInterfaces[].{Id:NetworkInterfaceId,Status:Status,Description:Description,Instance:Attachment.InstanceId,Subnet:SubnetId}" --output table
aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc" --region $region --output table
aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$vpc" --region $region --output table
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc" --region $region --query "RouteTables[].{Id:RouteTableId,Associations:Associations[].{Subnet:SubnetId,Main:Main}}" --output json
aws ec2 describe-vpc-peering-connections --filters "Name=requester-vpc-info.vpc-id,Values=$vpc" --region $region --output table
aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$vpc" --region $region --output table
aws ec2 describe-instances --filters "Name=vpc-id,Values=$vpc" --region $region --query "Reservations[].Instances[].{Id:InstanceId,State:State.Name,Subnet:SubnetId,SecurityGroups:SecurityGroups[].GroupId}" --output table
```

Inspect ALBs and target groups in the region:

```powershell
aws elbv2 describe-load-balancers --region ap-southeast-1 --query "LoadBalancers[].{Name:LoadBalancerName,Vpc:VpcId,State:State.Code}" --output table
aws elbv2 describe-target-groups --region ap-southeast-1 --query "TargetGroups[].{Name:TargetGroupName,Vpc:VpcId,Arn:TargetGroupArn}" --output table
```

If keeping an existing ALB, Terraform must manage compatible resources in the
ALB's VPC. An imported target group in another VPC cannot be used by that ALB.
Adopting a VPC is a coordinated state/configuration change; do not run `apply`
until the plan has been checked for unintended resource replacement.

## 7. VPC quota reached

Check which account is active and list the VPCs before considering any cleanup:

```powershell
aws sts get-caller-identity
aws ec2 describe-vpcs --region ap-southeast-1 --query "Vpcs[].{VpcId:VpcId,Default:IsDefault,Cidr:CidrBlock,Name:Tags[?Key=='Name']|[0].Value}" --output table
```

Inventory project VPCs (replace the IDs with the current VPC list):

```powershell
$region = "ap-southeast-1"
$vpcs = @("vpc-REPLACE-WITH-VERIFIED-ID-1", "vpc-REPLACE-WITH-VERIFIED-ID-2")

foreach ($vpc in $vpcs) {
  Write-Output "`n===== $vpc : SUBNETS ====="
  aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc" --region $region --query "Subnets[].{Id:SubnetId,Cidr:CidrBlock,Name:Tags[?Key=='Name']|[0].Value}" --output table
  Write-Output "`n===== $vpc : INSTANCES ====="
  aws ec2 describe-instances --filters "Name=vpc-id,Values=$vpc" --region $region --query "Reservations[].Instances[].{Id:InstanceId,State:State.Name,Subnet:SubnetId,Name:Tags[?Key=='Name']|[0].Value}" --output table
  Write-Output "`n===== $vpc : NAT GATEWAYS ====="
  aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpc" --region $region --query "NatGateways[].{Id:NatGatewayId,State:State,Subnet:SubnetId}" --output table
  Write-Output "`n===== $vpc : INTERNET GATEWAYS ====="
  aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc" --region $region --query "InternetGateways[].InternetGatewayId" --output table
  Write-Output "`n===== $vpc : NETWORK INTERFACES ====="
  aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$vpc" --region $region --query "NetworkInterfaces[].{Id:NetworkInterfaceId,Status:Status,Description:Description,Instance:Attachment.InstanceId}" --output table
}

Write-Output "`n===== LOAD BALANCERS IN REGION ====="
aws elbv2 describe-load-balancers --region $region --query "LoadBalancers[].{Name:LoadBalancerName,Vpc:VpcId,State:State.Code}" --output table

Write-Output "`n===== TERRAFORM STATE ====="
terraform state list
```

Do not delete the default VPC or any VPC containing resources you need. If
there are no safe VPCs to remove, request a regional VPC quota increase in
AWS Service Quotas or change the design to reuse an existing VPC.

## 8. Destroy Terraform-managed project infrastructure

Use this when intentionally removing infrastructure tracked in the active
state. First back up state (section 2), then inspect the destroy plan:

```powershell
terraform plan -destroy
```

If the plan only contains resources intended for removal, destroy them:

```powershell
terraform destroy
```

This does not remove untracked AWS resources, nor should it remove the S3
backend bucket because that bucket is not part of the root infrastructure
state.

## 9. Manually remove untracked project resources

Manual AWS deletion is only for resources verified as disposable and not
managed by the active Terraform state. The order is important: delete the
load balancer/instances first, wait for NAT gateways, then remove security
groups, subnets, route tables, internet gateways, and finally VPCs. Any
dependency error means stop and inspect remaining dependencies.

### 9.1 Current inventory and dry-run checks

Get current VPC IDs and resource details first (section 6 and section 7).
Use a command's `--dry-run` option where the AWS API supports it. Do not use
the historical IDs in section 10 without re-verifying each one.

For a currently verified load balancer:

```powershell
$albArn = aws elbv2 describe-load-balancers --names terraform-aws-project-alb --region ap-southeast-1 --query "LoadBalancers[0].LoadBalancerArn" --output text
aws elbv2 delete-load-balancer --load-balancer-arn $albArn --region ap-southeast-1
aws elbv2 wait load-balancers-deleted --load-balancer-arns $albArn --region ap-southeast-1
```

Terminate only verified disposable EC2 instances, then wait:

```powershell
aws ec2 terminate-instances --instance-ids <verified-instance-id> --region ap-southeast-1
aws ec2 wait instance-terminated --instance-ids <verified-instance-id> --region ap-southeast-1
```

Delete a verified NAT gateway, wait for deletion, and only then release the
Elastic IP associated with that NAT gateway:

```powershell
aws ec2 delete-nat-gateway --nat-gateway-id <verified-nat-gateway-id> --region ap-southeast-1
aws ec2 wait nat-gateway-deleted --nat-gateway-ids <verified-nat-gateway-id> --region ap-southeast-1
aws ec2 release-address --allocation-id <verified-nat-eip-allocation-id> --region ap-southeast-1
```

Delete verified subnets and non-main route tables. Do not delete a main route
table directly:

```powershell
aws ec2 delete-subnet --subnet-id <verified-subnet-id> --region ap-southeast-1
aws ec2 delete-route-table --route-table-id <verified-non-main-route-table-id> --region ap-southeast-1
```

Detach and delete a verified internet gateway:

```powershell
aws ec2 detach-internet-gateway --internet-gateway-id <verified-igw-id> --vpc-id <verified-vpc-id> --region ap-southeast-1
aws ec2 delete-internet-gateway --internet-gateway-id <verified-igw-id> --region ap-southeast-1
```

Delete a VPC only after its dependent resources have been removed:

```powershell
aws ec2 delete-vpc --vpc-id <verified-empty-vpc-id> --region ap-southeast-1
```

`DependencyViolation` means something remains attached. Check subnets,
instances/ENIs, NAT gateways, internet gateways, VPC endpoints, peering, and
security groups. Do not force-delete an ENI that is owned by an AWS service.

## 10. Historical resource IDs from this troubleshooting session

These IDs appeared in command output earlier in the conversation. They are
included for traceability, **not as current instructions**. Some resources
were subsequently deleted, and later runs created additional VPCs. Re-run
AWS inventory commands and confirm every resource still exists and is safe to
delete before using any ID below. Never run the entire list blindly.

Historical project VPCs:

```text
vpc-0beabb37e4d9acebb
vpc-0549378ef01e13f07
vpc-025bb44a94757d994
vpc-0d53945c9e33f99a5
```

The default VPC observed was `vpc-04cdc2e4eb7c41cbc`; do not delete it as
part of project cleanup.

Historical instances, NAT gateways, EIP allocations, and internet gateways:

```text
Instances:
i-0f52193c72c120603
i-0159d2fec77309d48
i-0e30a979e0cdcd8a2
i-06a4f534001466aa3

NAT gateways:
nat-079a312d609d9352d
nat-06c49951601b72ba2
nat-05e5740f141d3a845
nat-03d7b27209e07152a

EIP allocations associated with NAT gateways:
eipalloc-08fe36c1855bd0d06
eipalloc-0e4b303b1a1c67786
eipalloc-0fa9785d13ce01680
eipalloc-078382a331b172a33

Internet gateways:
igw-0b4a1e96aa6cba39c
igw-05a91bc2c604242c6
igw-08b83a9b3e62eed10
igw-0aecce853ab6d3d11
```

An unattached EIP `eipalloc-002d1199a48091a8c` was also observed. It was not
identified as belonging to a project NAT gateway; do not release it unless
you independently confirm ownership and that it is unused.

Historical project security groups:

```text
sg-01852d43353cc1639
sg-0abb75fa885f3e3aa
sg-001c31710b9bf7482
sg-03b19a57261266b4a
sg-0a9bcb60b2631616e
sg-0e8eab350ee6cfe2e
sg-0143f79300310fdba
sg-0e6f6d7d5d45bb968
```

When a security-group rule references another group, revoke the current
verified rule before deleting the groups. An earlier observed example was:

```powershell
aws ec2 revoke-security-group-ingress --group-id sg-0abb75fa885f3e3aa --protocol tcp --port 80 --source-group sg-01852d43353cc1639 --region ap-southeast-1
```

Verify that the rule still exists and matches the current groups before using
that command.

Historical subnet IDs:

```text
vpc-0beabb37e4d9acebb:
subnet-02f1d53d208cf9518
subnet-0a2eaf51b6759f70a
subnet-0a0f0b6a0711a1923
subnet-0088beeaab28bf90f

vpc-0d53945c9e33f99a5:
subnet-0359098ec6dd242b7
subnet-0d4885055903e1fca
subnet-05bcf6a3733b7ebaf
subnet-0975dac28c52464fa

vpc-0549378ef01e13f07:
subnet-094da8c05b7c8c969
subnet-08369b45a20b191bf
subnet-0edb49a9e763788cd
subnet-063caf2066f2e30e1

vpc-025bb44a94757d994:
subnet-05029b473f98bc6e7
subnet-057ab695054898ea3
subnet-07af7393ed996e2d5
subnet-0b35c9b930935d3d0
```

Historical non-main route tables:

```text
vpc-0beabb37e4d9acebb: rtb-0e5cc8bc6d4c6cff4
vpc-0d53945c9e33f99a5: rtb-049d05a72ed0a1eb0
vpc-0549378ef01e13f07: rtb-0fc14a40a9fdce95a
vpc-025bb44a94757d994:
rtb-0efd2bcc4cd544bf1
rtb-00b012fe14bd591a9
```

### Historical cleanup commands (do not run without re-verification)

The commands below were previously suggested for resources observed at that
time. Use them only after confirming the IDs are still present, belong to
this project, and contain nothing that must be kept. Stop on the first error.

```powershell
# Historical ALB (only if it still exists and should be deleted)
aws elbv2 delete-load-balancer --load-balancer-arn arn:aws:elasticloadbalancing:ap-southeast-1:843282289436:loadbalancer/app/terraform-aws-project-alb/163725f492988f4b --region ap-southeast-1
aws elbv2 wait load-balancers-deleted --load-balancer-arns arn:aws:elasticloadbalancing:ap-southeast-1:843282289436:loadbalancer/app/terraform-aws-project-alb/163725f492988f4b --region ap-southeast-1

# Historical EC2 instances (terminate only if verified disposable)
aws ec2 terminate-instances --instance-ids i-0159d2fec77309d48 i-0e30a979e0cdcd8a2 --region ap-southeast-1
aws ec2 wait instance-terminated --instance-ids i-0159d2fec77309d48 i-0e30a979e0cdcd8a2 --region ap-southeast-1
aws ec2 terminate-instances --instance-ids i-0f52193c72c120603 i-06a4f534001466aa3 --region ap-southeast-1
aws ec2 wait instance-terminated --instance-ids i-0f52193c72c120603 i-06a4f534001466aa3 --region ap-southeast-1

# Historical NAT gateways and associated EIPs
aws ec2 delete-nat-gateway --nat-gateway-id nat-06c49951601b72ba2 --region ap-southeast-1
aws ec2 delete-nat-gateway --nat-gateway-id nat-05e5740f141d3a845 --region ap-southeast-1
aws ec2 wait nat-gateway-deleted --nat-gateway-ids nat-06c49951601b72ba2 nat-05e5740f141d3a845 --region ap-southeast-1
aws ec2 release-address --allocation-id eipalloc-0e4b303b1a1c67786 --region ap-southeast-1
aws ec2 release-address --allocation-id eipalloc-0fa9785d13ce01680 --region ap-southeast-1

aws ec2 delete-nat-gateway --nat-gateway-id nat-079a312d609d9352d --region ap-southeast-1
aws ec2 delete-nat-gateway --nat-gateway-id nat-03d7b27209e07152a --region ap-southeast-1
aws ec2 wait nat-gateway-deleted --nat-gateway-ids nat-079a312d609d9352d nat-03d7b27209e07152a --region ap-southeast-1
aws ec2 release-address --allocation-id eipalloc-08fe36c1855bd0d06 --region ap-southeast-1
aws ec2 release-address --allocation-id eipalloc-078382a331b172a33 --region ap-southeast-1

# Historical security-group reference and project groups
aws ec2 revoke-security-group-ingress --group-id sg-0abb75fa885f3e3aa --protocol tcp --port 80 --source-group sg-01852d43353cc1639 --region ap-southeast-1
aws ec2 revoke-security-group-ingress --group-id sg-03b19a57261266b4a --protocol tcp --port 80 --source-group sg-001c31710b9bf7482 --region ap-southeast-1
aws ec2 delete-security-group --group-id sg-01852d43353cc1639 --region ap-southeast-1
aws ec2 delete-security-group --group-id sg-0abb75fa885f3e3aa --region ap-southeast-1
aws ec2 delete-security-group --group-id sg-001c31710b9bf7482 --region ap-southeast-1
aws ec2 delete-security-group --group-id sg-03b19a57261266b4a --region ap-southeast-1
aws ec2 delete-security-group --group-id sg-0a9bcb60b2631616e --region ap-southeast-1
aws ec2 delete-security-group --group-id sg-0e8eab350ee6cfe2e --region ap-southeast-1
aws ec2 delete-security-group --group-id sg-0143f79300310fdba --region ap-southeast-1
aws ec2 delete-security-group --group-id sg-0e6f6d7d5d45bb968 --region ap-southeast-1

# Historical subnets from the two active VPCs at that time
aws ec2 delete-subnet --subnet-id subnet-02f1d53d208cf9518 --region ap-southeast-1
aws ec2 delete-subnet --subnet-id subnet-0a2eaf51b6759f70a --region ap-southeast-1
aws ec2 delete-subnet --subnet-id subnet-0a0f0b6a0711a1923 --region ap-southeast-1
aws ec2 delete-subnet --subnet-id subnet-0088beeaab28bf90f --region ap-southeast-1
aws ec2 delete-subnet --subnet-id subnet-0359098ec6dd242b7 --region ap-southeast-1
aws ec2 delete-subnet --subnet-id subnet-0d4885055903e1fca --region ap-southeast-1
aws ec2 delete-subnet --subnet-id subnet-05bcf6a3733b7ebaf --region ap-southeast-1
aws ec2 delete-subnet --subnet-id subnet-0975dac28c52464fa --region ap-southeast-1

# Historical non-main route tables
aws ec2 delete-route-table --route-table-id rtb-0e5cc8bc6d4c6cff4 --region ap-southeast-1
aws ec2 delete-route-table --route-table-id rtb-049d05a72ed0a1eb0 --region ap-southeast-1

# Historical internet gateways
aws ec2 detach-internet-gateway --internet-gateway-id igw-0b4a1e96aa6cba39c --vpc-id vpc-0beabb37e4d9acebb --region ap-southeast-1
aws ec2 delete-internet-gateway --internet-gateway-id igw-0b4a1e96aa6cba39c --region ap-southeast-1
aws ec2 detach-internet-gateway --internet-gateway-id igw-0aecce853ab6d3d11 --vpc-id vpc-0d53945c9e33f99a5 --region ap-southeast-1
aws ec2 delete-internet-gateway --internet-gateway-id igw-0aecce853ab6d3d11 --region ap-southeast-1

# Historical VPCs (only after verifying they are empty and disposable)
aws ec2 delete-vpc --vpc-id vpc-0beabb37e4d9acebb --region ap-southeast-1
aws ec2 delete-vpc --vpc-id vpc-0549378ef01e13f07 --region ap-southeast-1
aws ec2 delete-vpc --vpc-id vpc-025bb44a94757d994 --region ap-southeast-1
aws ec2 delete-vpc --vpc-id vpc-0d53945c9e33f99a5 --region ap-southeast-1
```

The order in this historical block is illustrative only; in a real cleanup,
wait for asynchronous AWS deletion operations to finish before deleting
dependent resources. It is safer to destroy resources through Terraform when
they are correctly tracked.

## 11. VPC deletion returns `DependencyViolation`

The error means AWS still sees a dependency. Use the exact VPC ID and region
from the failed command, then inspect:

```powershell
$region = "ap-southeast-1"
$vpc = "vpc-REPLACE-WITH-VERIFIED-ID"

aws ec2 describe-subnets --filters "Name=vpc-id,Values=$vpc" --region $region --output table
aws ec2 describe-nat-gateways --filter "Name=vpc-id,Values=$vpc" --region $region --query "NatGateways[].{Id:NatGatewayId,State:State,Subnet:SubnetId}" --output table
aws ec2 describe-network-interfaces --filters "Name=vpc-id,Values=$vpc" --region $region --query "NetworkInterfaces[].{Id:NetworkInterfaceId,Status:Status,Description:Description,Instance:Attachment.InstanceId,Subnet:SubnetId}" --output table
aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$vpc" --region $region --output table
aws ec2 describe-vpc-endpoints --filters "Name=vpc-id,Values=$vpc" --region $region --output table
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$vpc" --region $region --query "RouteTables[].{Id:RouteTableId,Associations:Associations[].{Subnet:SubnetId,Main:Main}}" --output json
aws ec2 describe-vpc-peering-connections --filters "Name=requester-vpc-info.vpc-id,Values=$vpc" --region $region --output table
```

If an instance is verified as disposable, terminate it and wait:

```powershell
aws ec2 terminate-instances --instance-ids <verified-instance-id> --region ap-southeast-1
aws ec2 wait instance-terminated --instance-ids <verified-instance-id> --region ap-southeast-1
```

Delete its subnets and any remaining dependencies only after the instance and
service-owned ENIs are gone. Do not manually delete an ENI that is still
attached or owned by a service.

## 12. Create fresh infrastructure after cleanup

Once the chosen project resources have been removed and the account has VPC
quota available, reconnect to the existing backend, review the plan, then
apply:

```powershell
terraform init -reconfigure -backend-config="backend.hcl"
terraform plan
terraform apply
```

The S3 backend bucket and state object should remain. Do not delete the bucket
to solve an EC2 VPC quota or duplicate-resource error.

## 13. Terraform state import/detach reference

Import only AWS resources that exist and are not already represented in the
active state. Back up state first (section 2), then verify the resource's VPC
and configuration compatibility.

The following exact addresses were used in earlier troubleshooting:

```powershell
terraform import module.alb.aws_lb.app <load-balancer-arn>
terraform import module.alb.aws_lb_target_group.web <target-group-arn>
```

An earlier suggestion to detach a large set of network/security/instance
addresses used this command:

```powershell
terraform state rm module.vpc.aws_vpc.main module.vpc.aws_internet_gateway.main module.vpc.aws_subnet.public_a module.vpc.aws_subnet.public_b module.vpc.aws_subnet.private_a module.vpc.aws_subnet.private_b module.vpc.aws_route_table.public module.vpc.aws_route_table.private module.vpc.aws_route_table_association.public_a module.vpc.aws_route_table_association.public_b module.vpc.aws_route_table_association.private_a module.vpc.aws_route_table_association.private_b module.vpc.aws_eip.nat module.vpc.aws_nat_gateway.main module.security.aws_security_group.alb module.security.aws_security_group.ec2 module.ec2.aws_instance.web
```

**Do not run that `state rm` command for cleanup.** It removes management
records, not AWS resources. Use it only when deliberately detaching precisely
those addresses after a state backup and a reviewed migration plan.
