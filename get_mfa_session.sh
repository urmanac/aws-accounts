# get-mfa-session.sh
# ACCOUNT_ID=123456789012
# USER=terraform-admin
# 
# MFA_CODE=$(op item get "$USER" --otp)
# 
# CREDS=$(aws sts get-session-token \
#   --serial-number arn:aws:iam::$ACCOUNT_ID:mfa/$USER \
#   --token-code $MFA_CODE \
#   --duration-seconds 3600)
# 
# export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r .Credentials.AccessKeyId)
# export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r .Credentials.SecretAccessKey)
# export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r .Credentials.SessionToken)
ACCOUNT_ID=**REMOVED**
USER=terraform-admin

MFA_CODE=$(op read "op://Kingdon/**REMOVED**/one-time password?attribute=otp")

CREDS=$(aws sts get-session-token \
  --serial-number arn:aws:iam::**REMOVED**:mfa/**REMOVED** \
  --token-code $MFA_CODE \
  --duration-seconds 3600)

export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r .Credentials.AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r .Credentials.SecretAccessKey)
export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r .Credentials.SessionToken)
