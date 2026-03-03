# send-wt-to-kindle

[![Send Watchtower to Kindle](https://github.com/kutyel/send-wt-to-kindle/actions/workflows/send-watchtower.yml/badge.svg?branch=main)](https://github.com/kutyel/send-wt-to-kindle/actions/workflows/send-watchtower.yml)

Automatically downloads the latest _La Atalaya_ (Watchtower study edition) in Spanish as EPUB from [jw.org](https://www.jw.org) and sends it to your Kindle via email.

Runs monthly via GitHub Actions (1st of each month), processing the current issue and up to 3 months ahead.

## Setup

### 1. Add repository secrets

Go to **Settings → Secrets and variables → Actions** and add:

| Secret            | Description                                |
| ----------------- | ------------------------------------------ |
| `SMTP_SERVER`     | e.g. `smtp.gmail.com`                      |
| `SMTP_PORT`       | e.g. `587` (default)                       |
| `SENDER_EMAIL`    | Gmail (or other) address used to send      |
| `SENDER_PASSWORD` | App password (not your regular password)   |
| `KINDLE_EMAIL`    | Your Kindle email (e.g. `name@kindle.com`) |

### 2. Approve the sender email in Amazon

Go to [Amazon → Manage Your Content and Devices → Preferences → Personal Document Settings](https://www.amazon.com/hz/mycd/myx#/home/settings/payment) and add your `SENDER_EMAIL` to the **Approved Personal Document E-mail List**.

### 3. Gmail App Password

If using Gmail, enable 2FA and create an [App Password](https://myaccount.google.com/apppasswords). Use that as `SENDER_PASSWORD`.

## Local usage

```bash
pip install -r requirements.txt

export SMTP_SERVER=smtp.gmail.com
export SMTP_PORT=587
export SENDER_EMAIL=you@gmail.com
export SENDER_PASSWORD=your-app-password
export KINDLE_EMAIL=you@kindle.com

python script.py
```
