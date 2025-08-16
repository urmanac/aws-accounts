This repo has been sanitized by BFG

```bash
export AWS_PROFILE=sb-bootstrap
export AWS_PROFILE=prod-bootstrap

source ./get_mfa_session.sh
```

You must have AWS Credentials in a file in ~/.aws/credentials, or export them
in environment variables.

The configuration in this Terraform module ensures that AWS Access Keys are
limited when they have not yet MFA'ed. And we can have Test and Prod.

Not too tall order for ChatGPT!

--Product of ChatGPT, generally
