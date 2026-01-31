.PHONY: prod-apply prod-plan apply-sb plan-sb prod-sts sandbox-sts import-sb import-prod \
	sunkworks-plan sunkworks-apply panic-button-dry panic-button-live sunkworks-mfa prestream-check

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

# =============================================================================
# Sunkworks Multi-Account Targets
# =============================================================================

sunkworks-plan:
	tofu plan -var-file=sunkworks.tfvars -state=sunkworks.tfstate -target=module.sunkworks_organization -target=module.sunkworks_scps

sunkworks-apply:
	tofu apply -var-file=sunkworks.tfvars -state=sunkworks.tfstate

# Panic Button - Emergency cost protection
panic-button-dry:
	@echo "🧪 Running panic button in DRY RUN mode..."
	aws lambda invoke \
		--function-name sunkworks-panic-button \
		--payload '{"dry_run": true}' \
		/tmp/panic-response.json && cat /tmp/panic-response.json | jq

panic-button-live:
	@echo "🚨 ACTIVATING PANIC BUTTON - This will stop all non-essential instances!"
	@read -p "Type 'PANIC' to confirm: " confirm && [ "$$confirm" = "PANIC" ] || exit 1
	aws lambda invoke \
		--function-name sunkworks-panic-button \
		--payload '{"dry_run": false}' \
		/tmp/panic-response.json && cat /tmp/panic-response.json | jq

panic-button-recover:
	@echo "🔄 Recovering from panic button..."
	@read -p "Enter manifest key (e.g., panic-button/recovery-20260131-143022.json): " key && \
	aws lambda invoke \
		--function-name sunkworks-panic-recovery \
		--payload "{\"manifest_key\": \"$$key\"}" \
		/tmp/recovery-response.json && cat /tmp/recovery-response.json | jq

# Pre-apply backup trigger
backup-before-apply:
	@echo "📦 Triggering pre-apply backup..."
	aws lambda invoke \
		--function-name sunkworks-pre-apply-backup \
		--payload '{}' \
		/tmp/backup-response.json && cat /tmp/backup-response.json | jq

# Enhanced MFA helpers
sunkworks-mfa:
	@echo "Source the MFA script first:"
	@echo "  source scripts/sunkworks-mfa.sh"
	@echo "  sunkworks_mfa sb"
	@echo "  sunkworks_mfa prod"

prestream-check:
	@echo "🎬 Pre-stream authentication check"
	@bash -c 'source scripts/sunkworks-planb.sh && sunkworks_prestream_check'

session-monitor:
	@bash -c 'source scripts/sunkworks-mfa.sh && sunkworks_session_monitor 60'
