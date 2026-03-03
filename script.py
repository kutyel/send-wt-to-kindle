import os
import sys
import json
import smtplib
import requests
import tempfile
from email.mime.multipart import MIMEMultipart
from email.mime.base import MIMEBase
from email.mime.text import MIMEText
from email import encoders
from datetime import datetime
from dateutil.relativedelta import relativedelta


API_URL = (
    "https://b.jw-cdn.org/apis/pub-media/GETPUBMEDIALINKS"
    "?issue={issue}&output=json&pub=w&fileformat=EPUB"
    "&alllangs=0&langwritten=S&txtCMSLang=S"
)

MONTHS_AHEAD = 3


def get_issue_codes():
    """Return issue codes (YYYYMM) from the current month up to MONTHS_AHEAD."""
    today = datetime.today()
    codes = []
    for i in range(MONTHS_AHEAD + 1):
        dt = today + relativedelta(months=i)
        codes.append(dt.strftime("%Y%m"))
    return codes


def fetch_epub_url(issue_code):
    """Call the jw.org pub-media API and return the EPUB download URL and filename."""
    url = API_URL.format(issue=issue_code)
    print(f"[*] Fetching metadata for issue {issue_code}...")
    resp = requests.get(url, timeout=30)
    resp.raise_for_status()
    data = resp.json()

    try:
        epub_info = data["files"]["S"]["EPUB"][0]["file"]
        epub_url = epub_info["url"]
        filename = epub_url.rsplit("/", 1)[-1]
        formatted_date = data.get("formattedDate", issue_code)
        print(f"    Found: {formatted_date} -> {filename}")
        return epub_url, filename
    except (KeyError, IndexError):
        print(f"    No EPUB found for issue {issue_code}, skipping.")
        return None, None


def download_epub(epub_url, dest_path):
    """Download the EPUB file to dest_path."""
    print(f"[*] Downloading {epub_url}...")
    resp = requests.get(epub_url, timeout=60)
    resp.raise_for_status()
    with open(dest_path, "wb") as f:
        f.write(resp.content)
    size_kb = len(resp.content) / 1024
    print(f"    Saved ({size_kb:.0f} KB)")


def send_to_kindle(filepath, filename):
    """Send an EPUB file to the Kindle email address via SMTP."""
    smtp_server = os.environ["SMTP_SERVER"]
    smtp_port = int(os.environ.get("SMTP_PORT", "587"))
    sender_email = os.environ["SENDER_EMAIL"]
    sender_password = os.environ["SENDER_PASSWORD"]
    kindle_email = os.environ["KINDLE_EMAIL"]

    msg = MIMEMultipart()
    msg["From"] = sender_email
    msg["To"] = kindle_email
    msg["Subject"] = "Watchtower"

    msg.attach(MIMEText("", "plain"))

    with open(filepath, "rb") as f:
        part = MIMEBase("application", "epub+zip")
        part.set_payload(f.read())
        encoders.encode_base64(part)
        part.add_header("Content-Disposition", f'attachment; filename="{filename}"')
        msg.attach(part)

    print(f"[*] Sending {filename} to {kindle_email}...")
    with smtplib.SMTP(smtp_server, smtp_port) as server:
        server.starttls()
        server.login(sender_email, sender_password)
        server.sendmail(sender_email, kindle_email, msg.as_string())
    print("    Sent successfully!")


def main():
    issue_codes = get_issue_codes()
    print(f"Issues to process: {issue_codes}\n")

    with tempfile.TemporaryDirectory() as tmpdir:
        for code in issue_codes:
            epub_url, filename = fetch_epub_url(code)
            if not epub_url:
                continue

            filepath = os.path.join(tmpdir, filename)
            try:
                download_epub(epub_url, filepath)
                send_to_kindle(filepath, filename)
            except Exception as e:
                print(f"    ERROR processing {code}: {e}", file=sys.stderr)

    print("\nDone.")


if __name__ == "__main__":
    main()
