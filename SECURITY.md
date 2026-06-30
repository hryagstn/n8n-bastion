# Security Policy

## Supported Versions

We actively support and patch security vulnerabilities in the following versions of **n8n-bastion**:

| Version | Supported          |
| ------- | ------------------ |
| v1.x    | :white_check_mark: |
| < v1.0  | :x:                |

## Reporting a Vulnerability

We take the security of our monitoring scripts and workflows very seriously. If you discover any security-related issues, please do not use the public issue tracker. Instead, please report them directly to the maintainer:

- **Email:** harry.agustiana@gmail.com

Please include the following information in your report:
- A detailed description of the vulnerability.
- Steps to reproduce the issue (and a proof of concept if available).
- The potential impact of the vulnerability.

We will acknowledge receipt of your vulnerability report within 48 hours and work with you to resolve the issue as quickly as possible.

## Security Practices

For maximum security when deploying **n8n-bastion**:
1. **Secure Your Webhook URLs:** Ensure your n8n webhook URLs utilize HTTPS and, if possible, incorporate token/authentication headers to verify that requests genuinely originate from your VPS sentinel.
2. **Restrict Script Access:** Limit read/write permissions on `/opt/n8n-bastion/` and scripts to root or authorized users only (`chmod 700` or similar).
3. **Keep n8n Updated:** Regularly update your n8n instance to get the latest security patches.
