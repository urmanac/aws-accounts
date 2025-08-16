.PHONY: prod-apply prod-plan apply-sb plan-sb prod-sts sandbox-sts import-sb import-prod

import-sb:
	tofu import -var-file=sb.tfvars -state=sb.tfstate 'module.bootstrap_admin.aws_iam_user.iamroot' terraform-admin
import-prod:
	tofu import -var-file=prod.tfvars -state=prod.tfstate 'module.bootstrap_admin.aws_iam_user.iamroot' terraform-admin
prod-apply:
	tofu apply -var-file=prod.tfvars -state=prod.tfstate
prod-plan:
	tofu plan -var-file=prod.tfvars -state=prod.tfstate
apply-sb:
	tofu apply -var-file=sb.tfvars -state=sb.tfstate
plan-sb:
	tofu plan -var-file=sb.tfvars -state=sb.tfstate

prod-sts:
	aws sts get-session-token \
		--serial-number arn:aws:iam::**REMOVED**:mfa/**REMOVED** \
		--token-code $(shell op read "op://Kingdon/**REMOVED**/one-time password?attribute=otp") \
		--profile terraform-admin-prod-mfa

sandbox-sts:
	aws sts get-session-token \
		--serial-number arn:aws:iam::**REMOVED**:mfa/**REMOVED** \
		--token-code $(shell op read "op://Kingdon/**REMOVED**/one-time password?attribute=otp") \
		--profile terraform-admin-sb-mfa
