# Claude Desktop AWS MCP Integration

**Date**: 2025-11-23  
**Branch**: `claude-desktop`  
**Status**: Documented for future use

## Overview

This document describes the AWS MCP (Model Context Protocol) server integration with Claude Desktop, allowing Claude to directly interact with AWS APIs for infrastructure management and exploration. This integration complements our Terraform/OpenTofu workflows by enabling ad-hoc AWS operations without modifying infrastructure-as-code.

## Why AWS MCP Integration?

### Use Cases

1. **Exploratory Operations**: Query AWS resources without writing Terraform data sources
2. **Ad-hoc Changes**: Make quick adjustments that don't warrant a Terraform change
3. **Debugging**: Investigate issues by directly querying AWS state
4. **Validation**: Verify Terraform changes took effect as expected
5. **Cross-Account Operations**: Work with multiple AWS profiles/accounts interactively

### Relationship to Terraform/OpenTofu

- **Terraform/OpenTofu**: For declarative infrastructure management, version controlled changes
- **AWS MCP**: For imperative operations, exploration, and tasks outside IaC scope
- **Stakpak** (future): Alternative tool with higher rate limits for complex operations

## MCP Configuration

### Claude Desktop Config Location

**macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`

### Configuration Content

```json
{
  "mcpServers": {
    "awslabs.aws-api-mcp-server": {
      "command": "uvx",
      "args": [
        "awslabs.aws-api-mcp-server@latest"
      ],
      "env": {
        "AWS_REGION": "eu-west-1",
        "AWS_PROFILE": "sb-terraform-mfa-session"
      }
    }
  },
  "preferences": {
    "quickEntryDictationShortcut": "capslock"
  }
}
```

### Configuration Fields

**Required fields:**
- **command**: `uvx` - Uses pipx/uvx to run the Python package without global install
- **args**: Package identifier from PyPI (`awslabs.aws-api-mcp-server@latest`)
- **env.AWS_REGION**: Default region for AWS operations (our primary: `eu-west-1`)
- **env.AWS_PROFILE**: AWS credentials profile to use

**Note**: Earlier versions of this doc mentioned `disabled` and `autoApprove` fields - these were speculative and do not actually work. To disable the MCP server, you must remove the entire server block from the config and restart Claude Desktop.

## Authentication Setup

### MFA Session Workflow

The AWS MCP server uses the `sb-terraform-mfa-session` profile, which contains temporary session credentials obtained via MFA. Here's the complete authentication flow:

#### 1. Source MFA Helper Script

```bash
cd /path/to/aws-accounts
source get_mfa_session.sh
```

This loads two functions:
- `aws_mfa`: Obtains MFA session tokens
- `save_mfa`: Saves tokens to AWS credentials file

#### 2. Set Environment and Get MFA Session

```bash
export AWS_PROFILE=sb-bootstrap  # or sb-terraform, prod-bootstrap, etc.
aws_mfa
```

**What happens:**
1. Reads configuration from `.env.{environment}` (e.g., `.env.sb`)
2. Fetches MFA token from 1Password via `op` CLI
3. Calls `aws sts get-session-token` with MFA device ARN
4. Exports session credentials to environment variables:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`
   - `AWS_SESSION_TOKEN`

#### 3. Save Session to Profile

```bash
save_mfa
```

This writes the temporary session credentials to the `sb-terraform-mfa-session` profile in `~/.aws/credentials`, making them available to Claude Desktop and other AWS tools.

### Session Duration

- **Default**: 1 hour (3600 seconds)
- **Renewal**: Re-run `aws_mfa && save_mfa` when session expires
- **Indicator**: Claude will receive authentication errors when session expires

### Environment Files

Each environment has its own configuration file (`.env.{env}`):

```bash
# Example: .env.sb
ACCOUNT_ID=123456789012
MFA_DEVICE_NAME=your-mfa-device-name
OP_VAULT_ITEM=op://Vault/Item/one-time password?attribute=otp
```

**Fields:**
- `ACCOUNT_ID`: AWS account number
- `MFA_DEVICE_NAME`: Name of your MFA device (from IAM console)
- `OP_VAULT_ITEM`: 1Password reference for TOTP/OTP token

## Using the AWS MCP Integration

### Available Operations

The AWS MCP server provides two primary functions:

#### 1. `suggest_aws_commands`

**Purpose**: Get suggestions when unsure of exact AWS CLI syntax

**Use when:**
- Exploring unfamiliar AWS services
- Need help with complex query syntax
- Want to see multiple approaches to a task

**Example:**
```
Human: "How do I list all EC2 instances with their public IPs?"
Claude uses: suggest_aws_commands("list EC2 instances with public IPs")
Returns: Suggested aws ec2 describe-instances commands with relevant filters
```

#### 2. `call_aws`

**Purpose**: Execute specific AWS CLI commands directly

**Use when:**
- You know exactly what command to run
- Confidence in the operation's safety
- Need immediate results

**Example:**
```
Human: "Show me all running instances in eu-west-1"
Claude uses: call_aws("aws ec2 describe-instances --region eu-west-1 --filters Name=instance-state-name,Values=running")
```

### Command Restrictions

For security and safety:
- NO shell pipes (`|`), redirects (`>`, `>>`), or operators
- NO shell command substitution (`$()`, backticks)
- NO bash/zsh utilities (grep, awk, sed, etc.)
- All filtering must use AWS CLI's built-in options (--filters, --query, etc.)

### Best Practices

1. **Start with suggestions**: Use `suggest_aws_commands` when exploring
2. **Use `call_aws` for known operations**: Direct execution when confident
3. **Be specific with regions**: Always include `--region` for clarity
4. **Use JMESPath queries**: Leverage `--query` for precise output formatting
5. **Check session status**: Renew MFA session if seeing auth errors

## Troubleshooting

### MCP Server Won't Connect

**Symptoms:**
- Claude can't see AWS tools
- "MCP server failed to start" errors

**Solutions:**
1. Check Claude Desktop config syntax (valid JSON)
2. Verify `uvx` is installed: `which uvx`
3. Check AWS credentials are valid: `aws sts get-caller-identity --profile sb-terraform-mfa-session`
4. Restart Claude Desktop completely (quit and reopen)

### Authentication Errors

**Symptoms:**
- "ExpiredToken" errors
- "Access Denied" messages

**Solutions:**
1. Check MFA session hasn't expired (1 hour limit)
2. Renew session: `aws_mfa && save_mfa`
3. Verify profile name matches config: `sb-terraform-mfa-session`
4. Check environment file has correct `ACCOUNT_ID`

### "MCP Server Stuck Connected"

**Symptoms:**
- MCP server still appears in Claude's available tools
- Server remains functional even after config changes

**Root Cause:**
- MCP servers are loaded when Claude Desktop starts
- Config changes only take effect after a complete restart
- There is no "disabled" flag that works without restart

**Solutions:**
1. Remove entire `awslabs.aws-api-mcp-server` block from config file:
   ```bash
   # Edit: ~/Library/Application Support/Claude/claude_desktop_config.json
   # Remove the entire "awslabs.aws-api-mcp-server" section
   ```
2. **Completely quit and restart Claude Desktop** (not just close window)
   - On macOS: Cmd+Q to quit, then reopen
   - Verify it's fully quit from Activity Monitor if needed
3. If still showing, clear Claude cache:
   ```bash
   rm -rf ~/Library/Application\ Support/Claude/mcp*
   ```
   Then restart Claude Desktop again

**Important**: Setting `"disabled": true` does NOT work - you must remove the config block entirely and restart.

## Integration with Other Tools

### Claude Code (CLI)

**Status**: Placeholder - documentation pending

Claude Code CLI can also use AWS MCP server, but configuration differs from Claude Desktop. Future documentation will cover:
- Claude Code config file location
- Profile management in CLI context
- Differences from Desktop integration

### Noclaude (claude-code-proxy + LiteLLM)

**Status**: Experimental

Noclaude routes Claude Code requests through alternative LLM backends (OpenAI, Groq, etc.) for cost savings. AWS MCP integration considerations:
- MCP servers are client-side (run by Claude Code/Desktop)
- Backend LLM doesn't affect MCP availability
- Authentication still uses local AWS credentials
- Future docs: best practices for MCP with alternate backends

### Stakpak

**Status**: Alternative to AWS MCP, evaluation pending

Stakpak promises higher rate limits and potentially better AWS integration. Consider for:
- High-volume operations
- Complex multi-account workflows
- Rate limit issues with AWS MCP

## Cost Considerations

### AWS API Calls

- Most AWS API calls are **free** (describe-*, list-*, get-*)
- Write operations (create-*, delete-*, modify-*) may have costs
- CloudWatch logging/monitoring may incur charges
- Claude Desktop makes API calls on your behalf - review carefully before approving

### MCP Server Costs

- **AWS MCP Server**: Free, open source
- **uvx/pipx**: Free, Python package runner
- **1Password CLI**: Free with 1Password subscription
- **Claude Desktop**: Uses existing Claude subscription

## Security Best Practices

1. **Minimal Permissions**: Use least-privilege IAM policies
2. **MFA Always**: Never skip MFA for production accounts
3. **Short Sessions**: 1-hour sessions reduce exposure window
4. **Review Commands**: Check what Claude proposes before execution
5. **Disconnect When Not Using**: Remove server block from config and restart Claude Desktop
6. **Separate Profiles**: Use dedicated profile for MCP (`*-mfa-session`)
7. **Audit Trails**: CloudTrail logs all API calls from MCP

## Future Enhancements

### Short Term
- [ ] Document Claude Code integration
- [ ] Create helper script for config management
- [ ] Add CloudWatch metrics for MCP usage
- [ ] Automate session renewal (background process)

### Medium Term
- [ ] Integrate Stakpak as alternative MCP server
- [ ] Multi-account switching without config changes
- [ ] Custom autoApprove rules for safe operations
- [ ] Session expiry notifications in Claude

### Long Term
- [ ] MCP server for OpenTofu/Terraform operations
- [ ] Cross-cloud MCP (AWS + Azure + GCP)
- [ ] Team collaboration features (shared sessions)

## Related Documentation

- [GitHub OIDC Integration](./github-oidc-integration.md) - CI/CD authentication
- [Identity Provider Migration](./identity-provider-migration.md) - IAM provider updates
- [DESKTOP.md](../DESKTOP.md) - AWS infrastructure design for CozyStack
- [get_mfa_session.sh](../get_mfa_session.sh) - MFA authentication script

## References

- [AWS MCP Server GitHub](https://github.com/awslabs/aws-api-mcp-server)
- [Model Context Protocol Spec](https://modelcontextprotocol.io/)
- [Claude Desktop MCP Documentation](https://docs.anthropic.com/claude/docs/mcp)
- [AWS CLI Reference](https://docs.aws.amazon.com/cli/latest/)
- [1Password CLI](https://developer.1password.com/docs/cli/)

---

**Last Updated**: 2025-11-23  
**Maintainer**: @urmanac  
**Branch**: claude-desktop
